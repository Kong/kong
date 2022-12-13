local constants = require("kong.constants")
local declarative = require("kong.db.declarative")
local tablepool = require("tablepool")
local isempty = require("table.isempty")
local isarray = require("table.isarray")
local nkeys = require("table.nkeys")
local buffer = require("string.buffer")


local tostring = tostring
local assert = assert
local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local sort = table.sort
local yield = require("kong.tools.utils").yield
local fetch_table = tablepool.fetch
local release_table = tablepool.release


local ngx_log = ngx.log
local ngx_null = ngx.null
local ngx_md5 = ngx.md5
local ngx_md5_bin = ngx.md5_bin


local ngx_DEBUG = ngx.DEBUG


local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local _log_prefix = "[clustering] "


local _M = {}


local function to_sorted_string(value, o)
  yield(true)

  if #o > 1000000 then
    o:set(ngx_md5_bin(o:tostring()))
  end

  if value == ngx_null then
    o:put("/null/")

  else
    local t = type(value)
    if t == "string" or t == "number" then
      o:put(value)

    elseif t == "boolean" then
      o:put(tostring(value))

    elseif t == "table" then
      if isempty(value) then
        o:put("{}")

      elseif isarray(value) then
        local count = #value
        if count == 1 then
          to_sorted_string(value[1], o)
        elseif count == 2 then
          to_sorted_string(value[1], o)
          o:put(";")
          to_sorted_string(value[2], o)

        elseif count == 3 then
          to_sorted_string(value[1], o)
          o:put(";")
          to_sorted_string(value[2], o)
          o:put(";")
          to_sorted_string(value[3], o)

        elseif count == 4 then
          to_sorted_string(value[1], o)
          o:put(";")
          to_sorted_string(value[2], o)
          o:put(";")
          to_sorted_string(value[3], o)
          o:put(";")
          to_sorted_string(value[4], o)

        elseif count == 5 then
          to_sorted_string(value[1], o)
          o:put(";")
          to_sorted_string(value[2], o)
          o:put(";")
          to_sorted_string(value[3], o)
          o:put(";")
          to_sorted_string(value[4], o)
          o:put(";")
          to_sorted_string(value[5], o)

        else
          for i = 1, count do
            to_sorted_string(value[i], o)
            o:put(";")
          end
        end

      else
        local count = nkeys(value)
        local keys = fetch_table("hash-calc", count, 0)
        local i = 0
        for k in pairs(value) do
          i = i + 1
          keys[i] = k
        end

        sort(keys)

        for i = 1, count do
          o:put(keys[i])
          o:put(":")
          to_sorted_string(value[keys[i]], o)
          o:put(";")
        end

        release_table("hash-calc", keys)
      end

    else
      error("invalid type to be sorted (JSON types are supported)")
    end
  end
end

local function calculate_hash(input, o)
  if input == nil then
    return DECLARATIVE_EMPTY_CONFIG_HASH
  end

  o:reset()
  to_sorted_string(input, o)
  return ngx_md5(o:tostring())
end


local function calculate_config_hash(config_table)
  local o = buffer.new()
  if type(config_table) ~= "table" then
    local config_hash = calculate_hash(config_table, o)
    return config_hash, { config = config_hash, }
  end

  local routes    = config_table.routes
  local services  = config_table.services
  local plugins   = config_table.plugins
  local upstreams = config_table.upstreams
  local targets   = config_table.targets

  local routes_hash = calculate_hash(routes, o)
  local services_hash = calculate_hash(services, o)
  local plugins_hash = calculate_hash(plugins, o)
  local upstreams_hash = calculate_hash(upstreams, o)
  local targets_hash = calculate_hash(targets, o)

  config_table.routes    = nil
  config_table.services  = nil
  config_table.plugins   = nil
  config_table.upstreams = nil
  config_table.targets   = nil

  local rest_hash = calculate_hash(config_table, o)
  local config_hash = ngx_md5(routes_hash    ..
                              services_hash  ..
                              plugins_hash   ..
                              upstreams_hash ..
                              targets_hash   ..
                              rest_hash)

  config_table.routes    = routes
  config_table.services  = services
  config_table.plugins   = plugins
  config_table.upstreams = upstreams
  config_table.targets   = targets

  return config_hash, {
    config    = config_hash,
    routes    = routes_hash,
    services  = services_hash,
    plugins   = plugins_hash,
    upstreams = upstreams_hash,
    targets   = targets_hash,
  }
end

local hash_fields = {
    "config",
    "routes",
    "services",
    "plugins",
    "upstreams",
    "targets",
  }

local function fill_empty_hashes(hashes)
  for _, field_name in ipairs(hash_fields) do
    hashes[field_name] = hashes[field_name] or DECLARATIVE_EMPTY_CONFIG_HASH
  end
end

function _M.update(declarative_config, config_table, config_hash, hashes)
  assert(type(config_table) == "table")

  if not config_hash then
    config_hash, hashes = calculate_config_hash(config_table)
  end

  if hashes then
    fill_empty_hashes(hashes)
  end

  local current_hash = declarative.get_current_hash()
  if current_hash == config_hash then
    ngx_log(ngx_DEBUG, _log_prefix, "same config received from control plane, ",
      "no need to reload")
    return true
  end

  local entities, err, _, meta, new_hash =
  declarative_config:parse_table(config_table, config_hash)
  if not entities then
    return nil, "bad config received from control plane " .. err
  end

  if current_hash == new_hash then
    ngx_log(ngx_DEBUG, _log_prefix, "same config received from control plane, ",
      "no need to reload")
    return true
  end

  -- NOTE: no worker mutex needed as this code can only be
  -- executed by worker 0

  local res
  res, err = declarative.load_into_cache_with_events(entities, meta, new_hash, hashes)
  if not res then
    return nil, err
  end

  return true
end


_M.calculate_config_hash = calculate_config_hash


return _M
