if ngx.config.subsystem ~= "http" then
  return {
    init_worker = function() end,
  }
end


-- http subsystem


local cjson       = require("cjson")
local constants   = require("kong.constants")
local kong_log    = require("resty.kong.log")


local ngx    = ngx
local log    = ngx.log
local ERR    = ngx.ERR
local NOTICE = ngx.NOTICE


local function set_log_level(worker, level, timeout)
  local ok, err = pcall(kong_log.set_log_level, level, timeout)
  if not ok then
    log(ERR, "worker" , worker, " failed setting log level: ", err)
    return
  end

  log(NOTICE, "log level changed to ", level, " for worker ", worker)
end


-- if worker has outdated log level (e.g. newly spawned), updated it
local function init_handler()
  local shm_log_level = ngx.shared.kong:get(constants.DYN_LOG_LEVEL_KEY)

  local cur_log_level = kong_log.get_log_level()
  local timeout = (tonumber(
                    ngx.shared.kong:get(constants.DYN_LOG_LEVEL_TIMEOUT_AT_KEY)) or 0)
                  - ngx.time()

  if shm_log_level and cur_log_level ~= shm_log_level and timeout > 0 then
    set_log_level(ngx.worker.id() or -1, shm_log_level, timeout)
  end
end


-- log level cluster event updates
local function cluster_handler(data)
  log(NOTICE, "log level cluster event received")

  if not data then
    kong.log.err("received empty data in cluster_events subscription")
    return
  end

  local ok, err = kong.worker_events.post("debug", "log_level", cjson.decode(data))

  if not ok then
    kong.log.err("failed broadcasting to workers: ", err)
    return
  end

  log(NOTICE, "log level event posted for node")
end


-- log level worker event updates
local function worker_handler(data)
  local worker = ngx.worker.id() or -1

  log(NOTICE, "log level worker event received for worker ", worker)

  set_log_level(worker, data.log_level, data.timeout)
end


local function init_worker()
  ngx.timer.at(0, init_handler)

  kong.cluster_events:subscribe("log_level", cluster_handler)

  kong.worker_events.register(worker_handler, "debug", "log_level")
end


return {
  init_worker = init_worker,
}
