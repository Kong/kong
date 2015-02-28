-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"

local _M = {}

local function log(premature, conf, message)
  local lower_type = string.lower(conf.type)
  if lower_type == "nginx_log" then
    ngx.log(ngx.INFO, cjson.encode(message))
  elseif lower_type == "tcp" then
    local ok, err
    local host = conf.host
    local port = conf.port
    local timeout = conf.timeout
    if not timeout then timeout = 60000 end

    local keepalive = conf.keepalive
    if not keepalive then keepalive = 10000 end

    local sock = ngx.socket.tcp()
    sock:settimeout(timeout)

    ok, err = sock:connect(host, port)
    if not ok then
      ngx.log(ngx.ERR, "failed to connect to " .. host .. ":" .. tostring(port) .. ": ", err)
      return
    end

    ok, err = sock:send(cjson.encode(message) .. "\r\n")
    if not ok then
      ngx.log(ngx.ERR, "failed to send data to " .. host .. ":" .. tostring(port) .. ": ", err)
    end

    ok, err = sock:setkeepalive(keepalive)
    if not ok then
      ngx.log(ngx.ERR, "failed to keepalive to " .. host .. ":" .. tostring(port) .. ": ", err)
      return
    end
  end
end

function _M.execute(conf)
  utils.create_timer(log, conf, ngx.ctx.log_message)
end

return _M
