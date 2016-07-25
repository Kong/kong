--
-- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:04
-- To change this template use File | Settings | File Templates.
--
local response, _ = require 'kong.yop.response'()
local next = next
local ngxVar = ngx.var

local _M = {}

_M.process = function(ctx)
  local whitelist = ctx.whitelist
  if whitelist == nil or next(whitelist) == nil then return end

  local ip = ngxVar.remote_addr
  if not whitelist[ip] then response.notAllowdIpException(ctx.appKey, ip) end
end
return _M
