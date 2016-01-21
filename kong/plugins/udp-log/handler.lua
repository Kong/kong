local cjson = require "cjson"
local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"

local UdpLogHandler = BasePlugin:extend()

UdpLogHandler.PRIORITY = 1

local function log(premature, conf, message)
  if premature then return end
  
  local host = conf.host
  local port = conf.port
  local timeout = conf.timeout

  local sock = ngx.socket.udp()
  sock:settimeout(timeout)

  local ok, err = sock:setpeername(host, port)
  if not ok then
    ngx.log(ngx.ERR, "failed to connect to "..host..":"..tostring(port)..": ", err)
    return
  end

  ok, err = sock:send(cjson.encode(message))
  if not ok then
    ngx.log(ngx.ERR, "failed to send data to ".. host..":"..tostring(port)..": ", err)
  end

  ok, err = sock:close()
  if not ok then
    ngx.log(ngx.ERR, "failed to close connection from "..host..":"..tostring(port)..": ", err)
    return
  end
end

function UdpLogHandler:new()
  UdpLogHandler.super.new(self, "udp-log")
end

function UdpLogHandler:log(conf)
  UdpLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  local ok, err = ngx.timer.at(0, log, conf, message)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
  end
end

return UdpLogHandler
