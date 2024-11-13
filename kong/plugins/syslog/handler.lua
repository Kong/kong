local lsyslog = require "lsyslog"
local cjson = require "cjson"
local sandbox = require "kong.tools.sandbox".sandbox
local kong_meta = require "kong.meta"


local kong = kong
local ngx = ngx
local timer_at = ngx.timer.at


local SENDER_NAME = "kong"

local LOG_PRIORITIES = {
  debug = 7,
  info = 6,
  notice = 5,
  warning = 4,
  err = 3,
  crit = 2,
  alert = 1,
  emerg = 0
}

local LOG_LEVELS = {
  debug = lsyslog.LOG_DEBUG,
  info = lsyslog.LOG_INFO,
  notice = lsyslog.LOG_NOTICE,
  warning = lsyslog.LOG_WARNING,
  err = lsyslog.LOG_ERR,
  crit = lsyslog.LOG_CRIT,
  alert = lsyslog.LOG_ALERT,
  emerg = lsyslog.LOG_EMERG,
}

local FACILITIES = {
  auth = lsyslog.FACILITY_AUTH,
  authpriv = lsyslog.FACILITY_AUTHPRIV,
  cron = lsyslog.FACILITY_CRON,
  daemon = lsyslog.FACILITY_DAEMON,
  ftp = lsyslog.FACILITY_FTP,
  kern = lsyslog.FACILITY_KERN,
  lpr = lsyslog.FACILITY_LPR,
  mail = lsyslog.FACILITY_MAIL,
  news = lsyslog.FACILITY_NEWS,
  syslog = lsyslog.FACILITY_SYSLOG,
  user = lsyslog.FACILITY_USER,
  uucp = lsyslog.FACILITY_UUCP,
  local0 = lsyslog.FACILITY_LOCAL0,
  local1 = lsyslog.FACILITY_LOCAL1,
  local2 = lsyslog.FACILITY_LOCAL2,
  local3 = lsyslog.FACILITY_LOCAL3,
  local4 = lsyslog.FACILITY_LOCAL4,
  local5 = lsyslog.FACILITY_LOCAL5,
  local6 = lsyslog.FACILITY_LOCAL6,
  local7 = lsyslog.FACILITY_LOCAL7
}

local sandbox_opts = { env = { kong = kong, ngx = ngx } }


local function send_to_syslog(log_level, severity, message, facility)
  if LOG_PRIORITIES[severity] <= LOG_PRIORITIES[log_level] then
    lsyslog.open(SENDER_NAME, FACILITIES[facility])
    lsyslog.log(LOG_LEVELS[severity], cjson.encode(message))
  end
end


local function log(premature, conf, message)
  if premature then
    return
  end

  if message.response.status >= 500 then
    send_to_syslog(conf.log_level, conf.server_errors_severity, message, conf.facility)

  elseif message.response.status >= 400 then
    send_to_syslog(conf.log_level, conf.client_errors_severity, message, conf.facility)

  else
    send_to_syslog(conf.log_level, conf.successful_severity, message, conf.facility)
  end
end


local SysLogHandler = {
  PRIORITY = 4,
  VERSION = kong_meta.version,
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
