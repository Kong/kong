local constants = require("kong.constants")
local declarative = require("kong.db.declarative")
local tablepool = require("tablepool")
local isempty = require("table.isempty")
local isarray = require("table.isarray")
local nkeys = require("table.nkeys")
local buffer = require("string.buffer")
local db_errors = require("kong.db.errors")


local tostring = tostring
local assert = assert
local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local sort = table.sort
local yield = require("kong.tools.yield").yield
local fetch_table = tablepool.fetch
local release_table = tablepool.release
local xpcall = xpcall


local ngx_log = ngx.log
local ngx_null = ngx.null
local ngx_md5 = ngx.md5
local ngx_md5_bin = ngx.md5_bin


local ngx_DEBUG = ngx.DEBUG


local DECLARATIVE_EMPTY_CONFIG_HASH = constants.DECLARATIVE_EMPTY_CONFIG_HASH
local ERRORS = constants.CLUSTERING_DATA_PLANE_ERROR
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


--- Errors returned from _M.update() should have these fields
---
---@class kong.clustering.config_helper.update.err_t.base
---
---@field name        string # identifier that can be used to classify the error type
---@field source      string # lua function that is responsible for this error
---@field message     string # error description/contents
---@field config_hash string


--- Error returned when something causes an exception to be thrown
---
---@class kong.clustering.config_helper.update.err_t.exception : kong.clustering.config_helper.update.err_t.base
---
---@field exception any    # value that was passed to `error()`
---@field traceback string # lua traceback of the exception


--- Error returned when the configuration received from the control plane is
--- not valid
---
---@class kong.clustering.config_helper.update.err_t.declarative : kong.clustering.config_helper.update.err_t.base
---
---@field flattened_errors table
---@field fields           table
---@field code?            integer


--- Error returned when the act of reloading the local configuration failed
---
---@class kong.clustering.config_helper.update.err_t.reload : kong.clustering.config_helper.update.err_t.base


---@alias kong.clustering.config_helper.update.err_t
---| kong.clustering.config_helper.update.err_t.exception
---| kong.clustering.config_helper.update.err_t.declarative
---| kong.clustering.config_helper.update.err_t.reload


---@param err_t kong.clustering.config_helper.update.err_t
---@param msg kong.clustering.config_helper.update.msg
local function format_error(err_t, msg)
  err_t.source       = err_t.source      or "kong.clustering.config_helper.update"
  err_t.name         = err_t.name        or ERRORS.GENERIC
  err_t.message      = err_t.message     or "an unexpected error occurred"
  err_t.config_hash  = msg.config_hash   or DECLARATIVE_EMPTY_CONFIG_HASH

  -- Declarative config parse errors will include all the input entities in
  -- the error table. Strip these out to keep the error payload size small.
  local errors = err_t.flattened_errors
  if type(errors) == "table" then
    for i = 1, #errors do
      local err = errors[i]
      if type(err) == "table" then
        err.entity = nil
      end
    end
  end
end


---@param err any # whatever was passed to `error()`
---@return kong.clustering.config_helper.update.err_t.exception err_t
local function format_exception(err)
  return {
    name      = ERRORS.RELOAD,
    source    = "kong.clustering.config_helper.update",
    message   = "an exception was raised while updating the configuration",
    exception = err,
    traceback = debug.traceback(tostring(err), 1),
  }
end


---@class kong.clustering.config_helper.update.msg : table
---
---@field config_table            table
---@field config_hash             string
---@field hashes                  table<string, string>


---@param declarative_config table
---@param msg kong.clustering.config_helper.update.msg
---
---@return boolean? success
---@return string? err
---@return kong.clustering.config_helper.update.err_t? err_t
local function update(declarative_config, msg)
  local config_table = msg.config_table
  local config_hash = msg.config_hash
  local hashes = msg.hashes

  assert(type(config_table) == "table")

  if not config_hash then
    config_hash, hashes = calculate_config_hash(config_table)

    -- update the message in-place with the calculated hashes so that this
    -- metadata can be used in error-reporting
    msg.config_hash = config_hash
    msg.hashes = hashes
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

  local entities, err, err_t, meta, new_hash =
    declarative_config:parse_table(config_table, config_hash)
  if not entities then
    ---@type kong.clustering.config_helper.update.err_t.declarative
    err_t = db_errors:declarative_config_flattened(err_t, config_table)

    err_t.name = ERRORS.CONFIG_PARSE
    err_t.source = "kong.db.declarative.parse_table"

    return nil, "bad config received from control plane " .. err, err_t
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
    ---@type kong.clustering.config_helper.update.err_t.reload
    err_t = {
      name = ERRORS.RELOAD,
      source = "kong.db.declarative.load_into_cache_with_events",
      message = err,
    }

    return nil, err, err_t
  end

  return true
end


---@param declarative_config table
---@param msg kong.clustering.config_helper.update.msg
---
---@return boolean? success
---@return string? err
---@return kong.clustering.config_helper.update.err_t? err_t
function _M.update(declarative_config, msg)
  local pok, ok_or_err, err, err_t = xpcall(update, format_exception,
                                            declarative_config, msg)

  local ok = pok and ok_or_err

  if not pok then
    err_t = ok_or_err --[[@as kong.clustering.config_helper.update.err_t.exception]]--
    -- format_exception() captures the original error in the .exception field
    err = err_t.exception or "unknown error"
  end

  if not ok and err_t then
    format_error(err_t, msg)
  end

  return ok, err, err_t
end



_M.calculate_config_hash = calculate_config_hash


return _M
