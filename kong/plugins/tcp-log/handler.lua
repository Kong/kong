local BasePlugin = require "kong.plugins.base_plugin"
local basic_serializer = require "kong.plugins.log-serializers.basic"
local cjson = require "cjson"

local TcpLogHandler = BasePlugin:extend()

TcpLogHandler.PRIORITY = 2
TcpLogHandler.VERSION = "0.1.0"

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

local function log(premature, conf, message)
  if premature then
    return
  end

  local ok, err
  local host = conf.host
  local port = conf.port
  local timeout = conf.timeout
  local keepalive = conf.keepalive

  local sock = ngx.socket.tcp()
  sock:settimeout(timeout)

  ok, err = sock:connect(host, port)
  if not ok then
    ngx.log(ngx.ERR, "[tcp-log] failed to connect to " .. host .. ":" .. tostring(port) .. ": ", err)
    return
  end

  ok, err = sock:send(cjson.encode(message) .. "\r\n")
  if not ok then
    ngx.log(ngx.ERR, "[tcp-log] failed to send data to " .. host .. ":" .. tostring(port) .. ": ", err)
  end

  ok, err = sock:setkeepalive(keepalive)
  if not ok then
    ngx.log(ngx.ERR, "[tcp-log] failed to keepalive to " .. host .. ":" .. tostring(port) .. ": ", err)
    return
  end
end

function TcpLogHandler:new()
  TcpLogHandler.super.new(self, "tcp-log")
end

function TcpLogHandler:access(conf)
  TcpLogHandler.super.access(self)  

  if conf.log_body and conf.max_body_size > 0 then
    ngx.ctx.request_body = get_body_data(conf.max_body_size)
    ngx.ctx.response_body = ""
  end
end

function TcpLogHandler:body_filter(conf)
  TcpLogHandler.super.body_filter(self)

  if conf.log_body and conf.max_body_size > 0 then
    local chunk = ngx.arg[1]
    local res_body = ngx.ctx.response_body .. (chunk or "")
    ngx.ctx.response_body = string.sub(res_body, 0, conf.max_body_size)
  end
end

function TcpLogHandler:log(conf)
  TcpLogHandler.super.log(self)

  local message = basic_serializer.serialize(ngx)
  local ok, err = ngx.timer.at(0, log, conf, message)
  if not ok then
    ngx.log(ngx.ERR, "[tcp-log] failed to create timer: ", err)
  end
end

return TcpLogHandler
