-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"
local utils = require "apenode.utils"

local _M = {}

function _M.execute()
  utils.create_timer(_M.log, ngx.ctx.log_message)
end

function _M.log(premature, message)

  local lower_type = string.lower(configuration.plugins.networklog.type)
  if lower_type == "log" then
    ngx.log(ngx.INFO, cjson.encode(message))
  elseif lower_type == "tcp" then

    local host = configuration.plugins.networklog.host
    local port = configuration.plugins.networklog.port
    local timeout = configuration.plugins.networklog.timeout
    if not timeout then timeout = 60000 end

    local keepalive = configuration.plugins.networklog.keepalive
    if not keepalive then keepalive = 10000 end

    local sock = ngx.socket.tcp()
    sock:settimeout(timeout)

    local ok, err = sock:connect(host, port)
    if not ok then
      ngx.log(ngx.ERR, "failed to connect to " .. host .. ":" .. tostring(port) .. ": ", err)
      return
    end

    local bytes, err = sock:send(cjson.encode(message) .. "\r\n")
    if not bytes then
      ngx.log(ngx.ERR, "failed to send data to " .. host .. ":" .. tostring(port) .. ": ", err)
    end

    local ok, err = sock:setkeepalive(keepalive)
    if not ok then
      ngx.log(ngx.ERR, "failed to keepalive to " .. host .. ":" .. tostring(port) .. ": ", err)
      return
    end

  end
end

return _M
