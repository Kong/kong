--
-- 参数名转换拦截器
-- -- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:04
-- To change this template use File | Settings | File Templates.
--
local pairs = pairs
local next = next

local _M = {}

_M.process = function(ctx)
  local transformer = ctx.transformer
  if transformer == nil or next(transformer) == nil then return end
  local parameters = ctx.parameters
  for name, value in pairs(transformer) do
    if parameters[name] then
      parameters[value] = parameters[name]
      parameters[name] = nil
    end
  end
  ctx.parameters = parameters
end

return _M
