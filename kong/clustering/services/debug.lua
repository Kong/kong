local _M = {}

local get_log_level                = require("resty.kong.log").get_log_level
local set_log_level                = require("resty.kong.log").set_log_level
local constants                    = require("kong.constants")

local LOG_LEVELS                   = constants.LOG_LEVELS
local DYN_LOG_LEVEL_KEY            = constants.DYN_LOG_LEVEL_KEY
local DYN_LOG_LEVEL_TIMEOUT_AT_KEY = constants.DYN_LOG_LEVEL_TIMEOUT_AT_KEY


local function rpc_get_log_level(_node_id)
  return get_log_level(LOG_LEVELS[kong.configuration.log_level])
end


local function rpc_set_log_level(_node_id, log_level, timeout)
  local timeout = math.ceil(timeout or 60)

  local cur_log_level = get_log_level(LOG_LEVELS[kong.configuration.log_level])

  if cur_log_level == log_level then
    local message = "log level is already " .. LOG_LEVELS[log_level]
    return nil, message
  end

  local ok, err = pcall(set_log_level, log_level, timeout)

  if not ok then
    local message = "failed setting log level: " .. err
    return nil, message
  end

  local data = {
    log_level = log_level,
    timeout = timeout,
  }

  -- broadcast to all workers in a node
  ok, err = kong.worker_events.post("debug", "log_level", data)

  if not ok then
    return nil, err
  end

  -- store in shm so that newly spawned workers can update their log levels
  ok, err = ngx.shared.kong:set(DYN_LOG_LEVEL_KEY, log_level, timeout)

  if not ok then
    return nil, err
  end

  ok, err = ngx.shared.kong:set(DYN_LOG_LEVEL_TIMEOUT_AT_KEY, ngx.time() + timeout, timeout)

  if not ok then
    return nil, err
  end

  return true
end


function _M.init(manager)
  manager.callbacks:register("kong.debug.v1.get_log_level", rpc_get_log_level)
  manager.callbacks:register("kong.debug.v1.set_log_level", rpc_set_log_level)
end


return _M
