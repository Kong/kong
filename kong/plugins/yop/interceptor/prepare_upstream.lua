--
--收尾拦截器，完成往后端java应用转发请求的准备工作

-- -- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:04
-- To change this template use File | Settings | File Templates.
--
local setUriArgs = ngx.req.set_uri_args
local setBodyData = ngx.req.set_body_data
local setHeader = ngx.req.set_header
local stringLen = string.len
local pairs = pairs
local ipairs = ipairs
local type = type

local ngxEncodeArgs = ngx.encode_args
local encodeOnceToString = ngx.escape_uri
local CONTENT_LENGTH = "content-length"


local _M = {}

_M.process = function(ctx)
  local originalParameters = ctx.parameters
  for key, value in pairs(originalParameters) do
    local t = type(value)
    if t == 'string' then value = encodeOnceToString(value)
    elseif t == 'table' then for i, e in ipairs(value) do value[i] = encodeOnceToString(e) end
    end
    originalParameters[key] = value
  end

  local parameters = ngxEncodeArgs(originalParameters)

  if ctx.method == "GET" then
    setUriArgs(parameters)
  else
    setBodyData(parameters)
    setHeader(CONTENT_LENGTH, stringLen(parameters))
  end
end

return _M
