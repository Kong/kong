local lsyslog = require "lsyslog"
local cjson = require "cjson"


local kong = kong
local ngx = ngx
local timer_at = ngx.timer.at
local upper = string.upper


local SENDER_NAME = "kong"
local LOG_LEVELS = {
  debug = 7,
  info = 6,
  notice = 5,
  warning = 4,
  err = 3,
  crit = 2,
  alert = 1,
  emerg = 0
}


local function send_to_syslog(log_level, severity, message)
  if LOG_LEVELS[severity] <= LOG_LEVELS[log_level] then
    lsyslog.open(SENDER_NAME, lsyslog.FACILITY_USER)
    lsyslog.log(lsyslog["LOG_" .. upper(severity)], cjson.encode(message))
  end
end


local function log(premature, conf, message)
  if premature then
    return
  end

  if message.response.status >= 500 then
    send_to_syslog(conf.log_level, conf.server_errors_severity, message)

  elseif message.response.status >= 400 then
    send_to_syslog(conf.log_level, conf.client_errors_severity, message)

  else
    send_to_syslog(conf.log_level, conf.successful_severity, message)
  end
end


local SysLogHandler = {
  PRIORITY = 4,
  VERSION = "2.0.1",
}


function SysLogHandler:log(conf)
  local message = kong.log.serialize()
  local ok, err = timer_at(0, log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return SysLogHandler
