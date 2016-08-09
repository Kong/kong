local BasePlugin = require "kong.plugins.base_plugin"

local ipairs = ipairs
local ngx = ngx
local pcall = pcall
local cjson = require 'cjson'

local initializeCtx = require 'kong.plugins.yop.interceptor.initialize_ctx'
local httpMethod = require 'kong.plugins.yop.interceptor.http_method'
local whitelist = require 'kong.plugins.yop.interceptor.whitelist'
local auth = require 'kong.plugins.yop.interceptor.auth'
local validate_sign = require 'kong.plugins.yop.interceptor.validate_sign'
local decrypt = require 'kong.plugins.yop.interceptor.decrypt'
local defaultValue = require 'kong.plugins.yop.interceptor.default_value'
local requestValidator = require 'kong.plugins.yop.interceptor.request_validator'
local requestTransformer = require 'kong.plugins.yop.interceptor.request_transformer'
local prepare_upstream = require 'kong.plugins.yop.interceptor.prepare_upstream'

local security_center = require 'kong.yop.security_center'
local response, _ = require 'kong.yop.response'()
local marshaller_util = require 'kong.plugins.yop.marshaller_util'

local interceptors = {
  initializeCtx, httpMethod, whitelist, auth ,decrypt, validate_sign,
  defaultValue, requestValidator, requestTransformer, prepare_upstream
}

local YopHandler = BasePlugin:extend()

function YopHandler:new()
  YopHandler.super.new(self, "yop")
end

function YopHandler:access()

  YopHandler.super.access(self)
  local ctx = {}
  for _, interceptor in ipairs(interceptors) do
    interceptor.process(ctx)
  end
end

local function handleResponse(body)
  -- 如果前面产生了错误或者异常,即前面调用了response.send()方法,则服务器返回的内容是个json字符串
  local status,message = pcall(cjson.decode,body)
  local signRet = ngx.ctx.parameters.signRet           -- 是否需要签名
  local encrypt = ngx.ctx.parameters.encrypt           -- 是否需要加密

  -- 能够被cjson解析说明,前面有异常,即 status == 'SUCCESS',
  if status then
    if signRet then
      message.sign = security_center.sign(body)
    end
    ngx.arg[1] = marshaller_util.marshlResponse(message)
  -- 没有错误或者异常
  else
    local r = response:new()
    if signRet or encrypt then
      local trimBizResult,bizResult = marshaller_util.marshal(ngx.ctx.body)
      -- 签名：先处理空格、换行；返回值为空也可签名
      if signRet then
        r.sign = security_center.sign(trimBizResult)
      end

      -- 加密：不处理空格、换行；返回值为空则不做加密
      if encrypt and bizResult~="" then
        r.result = security_center.encrypt(bizResult)
      end
    end

    -- 无法直接序列化response,因为response中含有function
    local resp = {}
    resp.state = r.state
    resp.result = r.result
    resp.ts = r.ts
    resp.sign = r.sign
    resp.error = r.error
    resp.stringResult = r.stringResult
    resp.format = r.format
    resp.validSign = r.validSign
    ngx.arg[1] = marshaller_util.marshlResponse(resp)
  end
end

function YopHandler:body_filter()
  YopHandler.super.body_filter(self)

  -- ngx.arg[2] 为fasle 意味着,body没有接收完.
  if(not ngx.arg[2]) then
      ngx.ctx.body = ngx.ctx.body..ngx.arg[1]
      ngx.arg[1] = nil    -- When setting nil or an empty Lua string value to ngx.arg[1], no data chunk will be passed to the downstream Nginx output filters at all.
  else
  -- body接收完全了
    handleResponse(ngx.ctx.body)
  end

end

YopHandler.PRIORITY = 800
return YopHandler