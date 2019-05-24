local serializers = require "kong.tools.log_serializers"
local cjson = require "cjson"

local TcpLogHandler = {}

TcpLogHandler.PRIORITY = 7
TcpLogHandler.VERSION = "2.0.0"

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

  if conf.tls then
    ok, err = sock:sslhandshake(true, conf.tls_sni, false)
    if not ok then
      ngx.log(ngx.ERR, "[tcp-log] failed to perform TLS handshake to ",
                       host, ":", port, ": ", err)
      return
    end
  end

  ok, err = sock:send(cjson.encode(message) .. "\n")
  if not ok then
    ngx.log(ngx.ERR, "[tcp-log] failed to send data to " .. host .. ":" .. tostring(port) .. ": ", err)
  end

  ok, err = sock:setkeepalive(keepalive)
  if not ok then
    ngx.log(ngx.ERR, "[tcp-log] failed to keepalive to " .. host .. ":" .. tostring(port) .. ": ", err)
    return
  end
end

local function get_serializer(name)
  return serializers.get_serializer(name)
end

function TcpLogHandler:access(conf)
  local ok, err = serializers.load_serializer(conf.serializer)
  if not ok then
    ngx.log(ngx.ERR, err)
  end
end

function TcpLogHandler:log(conf)
  local serialize, err = get_serializer(conf.serializer)
  if not serialize then
    ngx.log(ngx.ERR, err)
    return
  end

  local message = serialize(ngx)

  local ok, err = ngx.timer.at(0, log, conf, message)
  if not ok then
    ngx.log(ngx.ERR, "[tcp-log] failed to create timer: ", err)
  end
end

return TcpLogHandler
