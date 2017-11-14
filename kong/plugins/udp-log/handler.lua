local BasePlugin = require "kong.plugins.base_plugin"
local serializer = require "kong.plugins.log-serializers.basic"
local cjson = require "cjson"

local timer_at = ngx.timer.at
local udp = ngx.socket.udp

local UdpLogHandler = BasePlugin:extend()

UdpLogHandler.PRIORITY = 8
UdpLogHandler.VERSION = "0.1.0"

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

function UdpLogHandler:new()
  UdpLogHandler.super.new(self, "udp-log")
end

function UdpLogHandler:access(conf)
  UdpLogHandler.super.access(self)  

  if conf.log_body then
    ngx.req.read_body()
    ngx.ctx.req_resp_bodies = {
      request_body = ngx.req.get_body_data(),
      response_body = ""
    }
  end
end

function UdpLogHandler:body_filter(conf)
  UdpLogHandler.super.body_filter(self)

  if conf.log_body then
    local chunk = ngx.arg[1]
    local req_resp_bodies = ngx.ctx.req_resp_bodies or { response_body = "" }
    req_resp_bodies.response_body = req_resp_bodies.response_body .. chunk
    ngx.ctx.req_resp_bodies = req_resp_bodies
  end
end

function UdpLogHandler:log(conf)
  UdpLogHandler.super.log(self)

  local ok, err = timer_at(0, log, conf, cjson.encode(serializer.serialize(ngx)))
  if not ok then
    ngx.log(ngx.ERR, "[udp-log] could not create timer: ", err)
  end
end

return UdpLogHandler
