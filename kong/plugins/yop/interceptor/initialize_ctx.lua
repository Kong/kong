--
-- 上下文初始化拦截器
-- -- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-23
-- Time: 下午12:18
-- To change this template use File | Settings | File Templates.
--
local readRequestBody = ngx.req.read_body
local getRequestBody = ngx.req.get_body_data
local ngxDecodeArgs = ngx.decode_args

local getRequestMethod = ngx.req.get_method

local cache = require 'kong.yop.cache'
local response, _ = require 'kong.yop.response'()

local ngxVar = ngx.var

local decodeOnceToString = ngx.unescape_uri

local _M = {}

local function decodeOnceToTable(body) if body then return ngxDecodeArgs(body) end return {} end

_M.process = function(ctx)
  local requestPath = ngx.ctx.api.request_path
  local apiUri = requestPath:gsub("/yop%-center", "")

  --  从缓存中获取api信息，如果不存在，就调用远程接口获取api信息并缓存
  local api = cache.cacheApi(apiUri)

  --  api校验
  if api == nil then response.apiNotExistException(apiUri) end
  if api.status ~= 'ACTIVE' then response.apiUnavailableException(apiUri) end

  local method = getRequestMethod()

  --  parameters需要做2次urldecode

  local original
  if method == 'GET' then
    original = ngxVar.args
  else
    readRequestBody()
    original = getRequestBody()
  end

  local parameters = decodeOnceToTable(decodeOnceToString(original))

  local appKey = parameters['appKey'] or parameters['customerNo']
  --  缺少appKey参数
  if appKey == nil then response.missParameterException("", "appKey") end

  local app = cache.cacheApp(appKey)
  --  app校验
  if app == nil or app.status ~= 'ACTIVE' then response.appUnavailableException(appKey) end

  --初始化ctx
  ctx.apiUri = apiUri
  ctx.api = api
  ctx.method = method
  ctx.appKey = appKey
  ctx.app = app
  ctx.parameters = parameters
  ctx.ip = ngxVar.remote_addr
  ctx.transformer = cache.cacheTransformer(apiUri)
  ctx.validator = cache.cacheValidator(apiUri)
  ctx.whitelist = cache.cacheIPWhitelist(apiUri)
  ctx.auth = cache.cacheAppAuth(appKey)
  ctx.defaultValues = cache.cacheDefaultValues(apiUri)
end

return _M

