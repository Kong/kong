local cjson = require "cjson"


local kong = kong
local ngx = ngx
local date = os.date
local tostring = tostring
local timer_at = ngx.timer.at
local udp = ngx.socket.udp
local concat = table.concat
local insert = table.insert


local function get_host_name()
  local f = io.popen("/bin/hostname")
  local hostname = f:read("*a") or ""
  f:close()
  hostname = string.gsub(hostname, "\n$", "")
  return hostname
end


local HOSTNAME = get_host_name()
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


local function merge(conf, message, pri)
  local tags_list = conf.tags
  local tags = {}
  for i = 1, #tags_list do
    insert(tags, "tag=" .. '"' .. tags_list[i] .. '"')
  end

  local udp_message = {
    "<" .. pri .. ">1",
    date("!%Y-%m-%dT%XZ"),
    HOSTNAME,
    SENDER_NAME,
    "-",
    "-",
    "[" .. conf.key .. "@41058", concat(tags, " ") .. "]",
    cjson.encode(message)
  }

  return concat(udp_message, " ")
end


local function send_to_loggly(conf, message, pri)
  local host = conf.host
  local port = conf.port
  local timeout = conf.timeout

  local udp_message = merge(conf, message, pri)

  local sock = udp()

  sock:settimeout(timeout)

  local ok, err = sock:setpeername(host, port)
  if not ok then
    kong.log.err("failed to connect to ", host, ":", tostring(port), ": ", err)
    return
  end

  local ok, err = sock:send(udp_message)
  if not ok then
    kong.log.err("failed to send data to ", host, ":", tostring(port), ": ", err)
  end

  local ok, err = sock:close()
  if not ok then
    kong.log.err("failed to close connection from ", host, ":", tostring(port), ": ", err)
    return
  end
end

local function decide_severity(conf, severity, message)
  if LOG_LEVELS[severity] > LOG_LEVELS[conf.log_level] then
    return
  end

  local pri = 8 + LOG_LEVELS[severity]
  return send_to_loggly(conf, message, pri)
end

local is_html = nil

local function log(premature, conf, message)
  if premature then
    return
  end

  if is_html == nil then
    is_html = ngx.config.subsystem == "http"
  end

  if is_html then
    if message.response.status >= 500 then
      return decide_severity(conf, conf.server_errors_severity, message)
    end

    if message.response.status >= 400 then
      return decide_severity(conf, conf.client_errors_severity, message)
    end
  end

  return decide_severity(conf, conf.successful_severity, message)
end


local LogglyLogHandler = {
  PRIORITY = 6,
  VERSION = "2.0.1",
}


function LogglyLogHandler:log(conf)
  local message = kong.log.serialize()

  local ok, err = timer_at(0, log, conf, message)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return LogglyLogHandler
