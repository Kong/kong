if ngx.config.subsystem ~= "http" then
  return {
    init_worker = function() end,
  }
end


local cjson       = require "cjson"
local constants   = require "kong.constants"


local LOG_LEVELS  = require("kong.constants").LOG_LEVELS


local log    = ngx.log
local ERR    = ngx.ERR
local NOTICE = ngx.NOTICE


-- http subsystem
local set_log_level = require("resty.kong.log").set_log_level
local get_log_level = require("resty.kong.log").get_log_level


local function init()
  local cur_log_level = get_log_level(LOG_LEVELS[kong.configuration.log_level])
  local shm_log_level = ngx.shared.kong:get(constants.DYN_LOG_LEVEL_KEY)
  local timeout = (tonumber(ngx.shared.kong:get(constants.DYN_LOG_LEVEL_TIMEOUT_AT_KEY)) or 0) - ngx.time()

  if shm_log_level and cur_log_level ~= shm_log_level and timeout > 0 then
    local ok, err = pcall(set_log_level, shm_log_level, timeout)
    if not ok then
      local worker = ngx.worker.id()
      log(ERR, "worker" , worker, " failed setting log level: ", err)
    end
  end
end


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


local function node_handler(data)
  local worker = ngx.worker.id()

  log(NOTICE, "log level worker event received for worker ", worker)

  local ok, err = pcall(set_log_level, data.log_level, data.timeout)

  if not ok then
    log(ERR, "worker ", worker, " failed setting log level: ", err)
    return
  end

  log(NOTICE, "log level changed to ", data.log_level, " for worker ", worker)
end


local function init_worker()
  ngx.timer.at(0, init)

  kong.cluster_events:subscribe("log_level", cluster_handler)

  kong.worker_events.register(node_handler, "debug", "log_level")
end


return {
  init_worker = init_worker,
}
