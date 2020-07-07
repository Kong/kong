local lsyslog = require "lsyslog"
local cjson = require "cjson"
local sandbox = require "kong.tools.sandbox".sandbox


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

local FACILITIES = {
  AUTH = lsyslog.AUTH,
  AUTHPRIV = lsyslog.AUTHPRIV,
  CRON = lsyslog.CRON,
  DAEMON = lsyslog.DAEMON,
  FTP = lsyslog.FTP,
  KERN = lsyslog.KERN,
  LPR = lsyslog.LPR,
  MAIL = lsyslog.MAIL,
  NEWS = lsyslog.NEWS,
  SYSLOG = lsyslog.SYSLOG,
  USER = lsyslog.USER,
  UUCP = lsyslog.UUCP,
  LOCAL0 = lsyslog.LOCAL0,
  LOCAL1 = lsyslog.LOCAL1,
  LOCAL2 = lsyslog.LOCAL2,
  LOCAL3 = lsyslog.LOCAL3,
  LOCAL4 = lsyslog.LOCAL4,
  LOCAL5 = lsyslog.LOCAL5,
  LOCAL6 = lsyslog.LOCAL6,
  LOCAL7 = lsyslog.LOCAL7
}

local sandbox_opts = { env = { kong = kong, ngx = ngx } }


local function send_to_syslog(log_level, severity, message, facility)
  if LOG_LEVELS[severity] <= LOG_LEVELS[log_level] then
    lsyslog.open(SENDER_NAME, FACILITIES[facility])
    lsyslog.log(lsyslog["LOG_" .. upper(severity)], cjson.encode(message))
  end
end

local function log(premature, conf, message)
  if premature then
    return
  end

  if message.response.status >= 500 then
    send_to_syslog(conf.log_level, conf.server_errors_severity, message, conf.syslog_facility)

  elseif message.response.status >= 400 then
    send_to_syslog(conf.log_level, conf.client_errors_severity, message, conf.syslog_facility)

  else
    send_to_syslog(conf.log_level, conf.successful_severity, message, conf.syslog_facility)
  end
end

local SysLogHandler = {
  PRIORITY = 4,
  VERSION = "2.1.0",
}


function SysLogHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression, sandbox_opts)())
    end
  end

  local message = kong.log.serialize()
  local ok, err = timer_at(0, log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return SysLogHandler
