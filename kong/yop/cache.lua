--
-- Created by IntelliJ IDEA.
-- User: zhangwenkang
-- Date: 16-7-22
-- Time: 下午4:46
-- To change this template use File | Settings | File Templates.
--
local json = require "cjson"
local cache = ngx.shared.yop
local httpClient = require "kong.yop.http_client"
local stringy = require "stringy"
local pairs = pairs
local next = next
local tostring = tostring

local url = os.getenv("YOP_HESSIAN")

local CACHE_KEYS = {
  API = "api:",
  APP = "app:",
  TRANSFORMER = "transformer:",
  VALIDATOR = "validator:",
  WHITELIST = "whitelist:",
  APP_AUTH = "appAuth:",
  DEFAULT_VALUES = "defaultValues:",
  SECRET = "secret:"
}

local _M = {}

function _M.rawset(key, value)
  return cache:set(key, value)
end

function _M.set(key, value)
  if value then
    value = json.encode(value)
  end

  return _M.rawset(key, value)
end

function _M.rawget(key)
  return cache:get(key)
end

function _M.get(key)
  local value, flags = _M.rawget(key)
  if value then value = json.decode(value) end
  return value, flags
end

function _M.delete(key) cache:delete(key) end

function _M.delete_all()
  cache:flush_all() -- This does not free up the memory, only marks the items as expired
  cache:flush_expired() -- This does actually remove the elements from the memory
end

function _M.get_or_set(original_key, key, cb)
  local value, err
  -- Try to get
  value = _M.get(key)
  if not value then
    -- Get from closure
    value, err = cb(original_key)
    if err then
      return nil, err
    elseif value then
      local ok, err = _M.set(key, value)
      if not ok then
        ngx.log(ngx.ERR, err)
      end
    end
  end
  return value
end

local function isEmptyTable(t)
  return next(t) == nil
end

local function remoteGetApi(api)
  ngx.log(ngx.INFO, "remote get api info...appKey:" .. api)
  local j = httpClient.post(url .. "/api", { apiUri = api, type = "basic" }, { ['accept'] = "application/json" })
  local o = json.decode(j)
  if isEmptyTable(o) then return nil end
  return o
end

local function remoteGetApp(appKey)
  ngx.log(ngx.INFO, "remote get app info...appKey:" .. appKey)
  local j = httpClient.post(url .. "/app", { appKey = appKey }, { ['accept'] = "application/json" })
  ngx.log(ngx.INFO,j)
  local o = json.decode(j)
  if isEmptyTable(o) then return nil end
  return o
end

local function remoteGetAppAuth(appKey)
  ngx.log(ngx.INFO, "remote get app auth info...appKey:" .. appKey)
  local j = httpClient.post(url .. "/auth", { appKey = appKey }, { ['accept'] = "application/json" })
  local o = json.decode(j)
  if isEmptyTable(o) then return {} end

  local auth = {}
  for _, value in pairs(o) do
    auth[tostring(value.apiId)] = true
  end
  return auth
end

local function remoteGetTransformer(api)
  ngx.log(ngx.INFO, "remote get api transformer info...api:" .. api)
  local j = httpClient.post(url .. "/api", { apiUri = api, type = "param" }, { ['accept'] = "application/json" })
  local o = json.decode(j)

  local transformer = {}
  for _, value in pairs(o) do
    local paramName = value.paramName
    local endParamName = value.endParamName
    if endParamName ~= nil and stringy.strip(endParamName) ~= '' and endParamName ~= paramName then
      transformer[paramName] = endParamName
    end
  end
  return transformer
end

local function remoteGetDefaultValues(api)
  ngx.log(ngx.INFO, "remote get api default values info...api:" .. api)
  local j = httpClient.post(url .. "/api", { apiUri = api, type = "param" }, { ['accept'] = "application/json" })
  local o = json.decode(j)

  local defaultValues = {}
  for _, value in pairs(o) do
    local defaultValue = value.defaultValue
    if defaultValue ~= nil then
      defaultValues[value.paramName] = defaultValue
    end
  end
  return defaultValues
end

local function remoteGetValidator(api)
  ngx.log(ngx.INFO, "remote get api validator info...api:" .. api)
  local j = httpClient.post(url .. "/api", { apiUri = api, type = "validator" }, { ['accept'] = "application/json" })
  return json.decode(j)
end

local function remoteGetIPWhitelist(api)
  ngx.log(ngx.INFO, "remote get api whitelist info...api:" .. api)
  local j = httpClient.post(url .. "/limit", { apiUri = api }, { ['accept'] = "application/json" })
  local o = json.decode(j)
  if isEmptyTable(o) then return {} end

  local whitelist = {}
  for _, value in pairs(o) do
    if value.limitType == 'WHITELIST' and value.status == 'ENABLE' then
      local whitelists = value.whitelist
      for _, w in pairs(whitelists) do
        whitelist[w] = true
      end
    end
  end
  return whitelist
end

function _M.cacheApi(api)
  return _M.get_or_set(api, CACHE_KEYS.API .. api, remoteGetApi)
end

function _M.cacheApp(app)
  return _M.get_or_set(app, CACHE_KEYS.APP .. app, remoteGetApp)
end

function _M.cacheTransformer(api)
  return _M.get_or_set(api, CACHE_KEYS.TRANSFORMER .. api, remoteGetTransformer)
end

function _M.cacheValidator(api)
  return _M.get_or_set(api, CACHE_KEYS.VALIDATOR .. api, remoteGetValidator)
end

function _M.cacheIPWhitelist(api)
  return _M.get_or_set(api, CACHE_KEYS.WHITELIST .. api, remoteGetIPWhitelist)
end

function _M.cacheAppAuth(appKey)
  return _M.get_or_set(appKey, CACHE_KEYS.APP_AUTH .. appKey, remoteGetAppAuth)
end

function _M.cacheDefaultValues(apiUri)
  return _M.get_or_set(apiUri, CACHE_KEYS.DEFAULT_VALUES .. apiUri, remoteGetDefaultValues)
end

return _M
