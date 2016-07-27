--
-- http请求方法拦截器
-- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:04
-- To change this template use File | Settings | File Templates.
--
local response, _ = require 'kong.yop.response'()

local _M = {}

_M.process = function(ctx)
  local allowedMethod = ctx.api.httpMethod
  local method = ctx.method
  if allowedMethod[1] ~= method and allowedMethod[2] ~= method then response.notAllowdHttpMethodException(ctx.appKey, ctx.method) end
end

return _M
