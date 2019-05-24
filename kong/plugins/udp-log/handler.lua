local serializers = require "kong.tools.log_serializers"
local cjson = require "cjson"

local timer_at = ngx.timer.at
local udp = ngx.socket.udp

local UdpLogHandler = {}

UdpLogHandler.PRIORITY = 8
UdpLogHandler.VERSION = "2.0.0"

local function log(premature, conf, str)
  if premature then
    return
  end

  local sock = udp()
  sock:settimeout(conf.timeout)

  local ok, err = sock:setpeername(conf.host, conf.port)
  if not ok then
    ngx.log(ngx.ERR, "[udp-log] could not connect to ", conf.host, ":", conf.port, ": ", err)
    return
  end

  ok, err = sock:send(str)
  if not ok then
    ngx.log(ngx.ERR, " [udp-log] could not send data to ", conf.host, ":", conf.port, ": ", err)
  else
    ngx.log(ngx.DEBUG, "[udp-log] sent: ", str)
  end

  ok, err = sock:close()
  if not ok then
    ngx.log(ngx.ERR, "[udp-log] could not close ", conf.host, ":", conf.port, ": ", err)
  end
end

local function get_serializer(name)
  return serializers.get_serializer(name)
end

function UdpLogHandler:access(conf)
  local ok, err = serializers.load_serializer(conf.serializer)
  if not ok then
    ngx.log(ngx.ERR, err)
  end
end

function UdpLogHandler:log(conf)
  local serialize, err = get_serializer(conf.serializer)
  if not serialize then
    ngx.log(ngx.ERR, err)
    return
  end

  local message = serialize(ngx)

  local ok, err = timer_at(0, log, conf, cjson.encode(message))
  if not ok then
    ngx.log(ngx.ERR, "[udp-log] could not create timer: ", err)
  end
end

return UdpLogHandler
