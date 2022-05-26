local constants = require("kong.constants")
local declarative = require("kong.db.declarative")

local tostring = tostring
local assert = assert
local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local concat = table.concat
local sort = table.sort

local isempty = require("table.isempty")
local isarray = require("table.isarray")
local nkeys = require("table.nkeys")
local new_tab = require("table.new")

local ngx_log = ngx.log
local ngx_null = ngx.null
local ngx_md5 = ngx.md5
local ngx_md5_bin = ngx.md5_bin

--local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG

local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local _log_prefix = "[clustering] "


local _M = {}
local _MT = { __index = _M, }


local function to_sorted_string(value)
  if value == ngx_null then
    return "/null/"
  end

  local t = type(value)
  if t == "string" or t == "number" then
    return value

  elseif t == "boolean" then
    return tostring(value)

  elseif t == "table" then
    if isempty(value) then
      return "{}"

    elseif isarray(value) then
      local count = #value
      if count == 1 then
        return to_sorted_string(value[1])

      elseif count == 2 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2])

      elseif count == 3 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3])

      elseif count == 4 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3]) .. ";" ..
               to_sorted_string(value[4])

      elseif count == 5 then
        return to_sorted_string(value[1]) .. ";" ..
               to_sorted_string(value[2]) .. ";" ..
               to_sorted_string(value[3]) .. ";" ..
               to_sorted_string(value[4]) .. ";" ..
               to_sorted_string(value[5])
      end

      local i = 0
      local o = new_tab(count < 100 and count or 100, 0)
      for j = 1, count do
        i = i + 1
        o[i] = to_sorted_string(value[j])

        if j % 100 == 0 then
          i = 1
          o[i] = ngx_md5_bin(concat(o, ";", 1, 100))
        end
      end

      return ngx_md5_bin(concat(o, ";", 1, i))

    else
      local count = nkeys(value)
      local keys = new_tab(count, 0)
      local i = 0
      for k in pairs(value) do
        i = i + 1
        keys[i] = k
      end

      sort(keys)

      local o = new_tab(count, 0)
      for i = 1, count do
        o[i] = keys[i] .. ":" .. to_sorted_string(value[keys[i]])
      end

      value = concat(o, ";", 1, count)

      return #value > 512 and ngx_md5_bin(value) or value
    end

  else
    error("invalid type to be sorted (JSON types are supported)")
  end
end

local function calculate_config_hash(config_table)
  if type(config_table) ~= "table" then
    local config_hash = ngx_md5(to_sorted_string(config_table))
    return config_hash, { config = config_hash, }
  end

  local routes    = config_table.routes
  local services  = config_table.services
  local plugins   = config_table.plugins
  local upstreams = config_table.upstreams
  local targets   = config_table.targets

  local routes_hash    = routes    and ngx_md5(to_sorted_string(routes))    or DECLARATIVE_EMPTY_CONFIG_HASH
  local services_hash  = services  and ngx_md5(to_sorted_string(services))  or DECLARATIVE_EMPTY_CONFIG_HASH
  local plugins_hash   = plugins   and ngx_md5(to_sorted_string(plugins))   or DECLARATIVE_EMPTY_CONFIG_HASH
  local upstreams_hash = upstreams and ngx_md5(to_sorted_string(upstreams)) or DECLARATIVE_EMPTY_CONFIG_HASH
  local targets_hash   = targets   and ngx_md5(to_sorted_string(targets))   or DECLARATIVE_EMPTY_CONFIG_HASH

  config_table.routes    = nil
  config_table.services  = nil
  config_table.plugins   = nil
  config_table.upstreams = nil
  config_table.targets   = nil

  local config_hash = ngx_md5(to_sorted_string(config_table) .. routes_hash
                                                             .. services_hash
                                                             .. plugins_hash
                                                             .. upstreams_hash
                                                             .. targets_hash)

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

local function fill_empty_hashes(hashes)
  for _, field_name in ipairs{
    "config",
    "routes",
    "services",
    "plugins",
    "upstreams",
    "targets",
  } do
    hashes[field_name] = hashes[field_name] or DECLARATIVE_EMPTY_CONFIG_HASH
  end
end

function _M.new(conf)
  local self = {
    declarative_config = declarative.new_config(conf),
  }

  return setmetatable(self, _MT)
end

function _M:execute(config_table, config_hash, hashes)
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
  self.declarative_config:parse_table(config_table, config_hash)
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
