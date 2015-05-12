local cjson = require "cjson"

local _M = {}

local function log(premature, conf, message)
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

  local ok, err = sock:send(cjson.encode(message))
  if not ok then
    ngx.log(ngx.ERR, "failed to send data to ".. host..":"..tostring(port)..": ", err)
  end

  local ok, err = sock:close()
  if not ok then
    ngx.log(ngx.ERR, "failed to close connection from "..host..":"..tostring(port)..": ", err)
    return
  end
end

function _M.execute(conf)
  local ok, err = ngx.timer.at(0, log, conf, ngx.ctx.log_message)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
  end
end

return _M
