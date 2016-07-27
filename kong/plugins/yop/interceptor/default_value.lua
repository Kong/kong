--
-- 默认值拦截器，设置参数的默认值
-- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:04
-- To change this template use File | Settings | File Templates.
--
local pairs = pairs
local _M = {}

_M.process = function(ctx)
  local defaultValues = ctx.defaultValues
  local parameters = ctx.parameters
  for key, value in pairs(defaultValues) do
    if parameters[key] == nil then
      if value == '#appKey#' or value == '#customerNo#' then parameters[key] = ctx.appKey
      elseif value == '#requestIp#' then parameters[key] = ctx.ip
      else parameters[key] = value
      end
    end
  end
end

return _M
