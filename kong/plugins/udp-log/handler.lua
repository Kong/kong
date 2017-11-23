local BasePlugin = require "kong.plugins.base_plugin"
local serializer = require "kong.plugins.log-serializers.basic"
local cjson = require "cjson"

local timer_at = ngx.timer.at
local udp = ngx.socket.udp

local UdpLogHandler = BasePlugin:extend()

UdpLogHandler.PRIORITY = 8
UdpLogHandler.VERSION = "0.1.0"

local function get_body_data(max_body_size)
  local req  = ngx.req
  
  req.read_body()
  local data  = req.get_body_data()
  if data then
    return string.sub(data, 0, max_body_size)
  end

  local file_path = req.get_body_file()
  if file_path then
    local file = io.open(file_path, "r")
    data       = file:read(max_body_size)
    file:close()
    return data
  end
  
  return ""
end

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

  if conf.log_body and conf.max_body_size > 0 then
    ngx.ctx.request_body = get_body_data(conf.max_body_size)
    ngx.ctx.response_body = ""
  end
end

function UdpLogHandler:body_filter(conf)
  UdpLogHandler.super.body_filter(self)

  if conf.log_body and conf.max_body_size > 0 then
    local chunk = ngx.arg[1]
    local res_body = ngx.ctx.response_body .. (chunk or "")
    ngx.ctx.response_body = string.sub(res_body, 0, conf.max_body_size)
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
