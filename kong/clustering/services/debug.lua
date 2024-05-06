local _M = {}


local resty_log = require("resty.kong.log")
local constants = require("kong.constants")


local tostring = tostring


local function rpc_set_log_level(_node_id, new_log_level, timeout)
  if not constants.LOG_LEVELS[new_log_level] then
    return nil, "unknown log level: " .. tostring(new_log_level)
  end

  if type(new_log_level) == "string" then
    new_log_level = constants.LOG_LEVELS[new_log_level]
  end

  local timeout = math.ceil(timeout or constants.DYN_LOG_LEVEL_DEFAULT_TIMEOUT)

  local _, _, original_level = resty_log.get_log_level()
  if new_log_level == original_level then
    timeout = 0
  end

  -- this function should not fail, if it throws exception, let RPC framework handle it
  resty_log.set_log_level(new_log_level, timeout)

  local data = {
    log_level = new_log_level,
    timeout = timeout,
  }
  -- broadcast to all workers in a node
  local ok, err = kong.worker_events.post("debug", "log_level", data)
  if not ok then
    return nil, err
  end

  -- store in shm so that newly spawned workers can update their log levels
  ok, err = ngx.shared.kong:set(constants.DYN_LOG_LEVEL_KEY, new_log_level, timeout)
  if not ok then
    return nil, err
  end

  ok, err = ngx.shared.kong:set(constants.DYN_LOG_LEVEL_TIMEOUT_AT_KEY, ngx.time() + timeout, timeout)
  if not ok then
    return nil, err
  end

  return true
end


local function rpc_get_log_level(_node_id)
  local current_level, timeout, original_level = resty_log.get_log_level()
  return { current_level = constants.LOG_LEVELS[current_level],
           timeout = timeout,
           original_level = constants.LOG_LEVELS[original_level],
         }
end


function _M.init(manager)
  manager.callbacks:register("kong.debug.log_level.v1.get_log_level", rpc_get_log_level)
  manager.callbacks:register("kong.debug.log_level.v1.set_log_level", rpc_set_log_level)
end


return _M
