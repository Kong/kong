local cjson = require "cjson"

local CACHE_KEYS = {
  APIS = "apis",
  CONSUMERS = "consumers",
  PLUGINS = "plugins",
  BASICAUTH_CREDENTIAL = "basicauth_credentials",
  KEYAUTH_CREDENTIAL = "keyauth_credentials",
  OAUTH2_CREDENTIAL = "oauth2_credentials",
  OAUTH2_TOKEN = "oauth2_token",
  ACLS = "acls",
  SSL = "ssl",
  REQUESTS = "requests",
  TIMERS = "timers"
}

local _M = {}

function _M.rawset(key, value, exptime)
  local cache = ngx.shared.cache
  return cache:set(key, value, exptime or 0)
end

function _M.set(key, value, exptime)
  if exptime == nil then
    exptime = configuration and configuration.database_cache_expiration or 0
  end

  if value then
    value = cjson.encode(value)
    ngx.log(ngx.DEBUG, " saving cache key \""..key.."\": "..value)
  end

  return _M.rawset(key, value, exptime)
end

function _M.rawget(key)
  ngx.log(ngx.DEBUG, " Try to get cache key \""..key.."\"")
  local cache = ngx.shared.cache
  return cache:get(key)

end

function _M.get(key)
  local value, flags = _M.rawget(key)
  if value then
    ngx.log(ngx.DEBUG, " Found cache value for key \""..key.."\": "..value)
    value = cjson.decode(value)
  end
  return value, flags
end

function _M.incr(key, value)
  local cache = ngx.shared.cache
  return cache:incr(key, value)
end

function _M.delete(key)
  local cache = ngx.shared.cache
  cache:delete(key)
end

function _M.requests_key()
  return CACHE_KEYS.REQUESTS
end

function _M.api_key(host)
  return CACHE_KEYS.APIS.."/"..host
end

function _M.consumer_key(id)
  return CACHE_KEYS.CONSUMERS.."/"..id
end

function _M.plugin_key(name, api_id, consumer_id)
  return CACHE_KEYS.PLUGINS.."/"..name.."/"..api_id..(consumer_id and "/"..consumer_id or "")
end

function _M.basicauth_credential_key(username)
  return CACHE_KEYS.BASICAUTH_CREDENTIAL.."/"..username
end

function _M.oauth2_credential_key(client_id)
  return CACHE_KEYS.OAUTH2_CREDENTIAL.."/"..client_id
end

function _M.oauth2_token_key(access_token)
  return CACHE_KEYS.OAUTH2_TOKEN.."/"..access_token
end

function _M.keyauth_credential_key(key)
  return CACHE_KEYS.KEYAUTH_CREDENTIAL.."/"..key
end

function _M.acls_key(consumer_id)
  return CACHE_KEYS.ACLS.."/"..consumer_id
end

function _M.ssl_data(api_id)
  return CACHE_KEYS.SSL.."/"..api_id
end

function _M.get_or_set(key, cb, exptime)
  local value, err
  -- Try to get
  value = _M.get(key)
  if not value then
    -- Get from closure
    value, err = cb()
    if err then
      return nil, err
    elseif value then
      local ok, err = _M.set(key, value, exptime)
      if not ok then
        ngx.log(ngx.ERR, err)
      end
    end
  end
  return value
end

return _M
