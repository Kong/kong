local cjson = require "cjson"
local constants = require "kong.constants"

local _M = {}

function _M.set(key, value, exptime)
  if exptime == nil then
    exptime = configuration and configuration.database_cache_expiration or 0
  end

  local cache = ngx.shared.cache
  if value then
    ngx.log(ngx.DEBUG, " saving cache key \""..key.."\": "..value)
    value = cjson.encode(value)
  end

  return cache:set(key, value, exptime)
end

function _M.get(key)
  ngx.log(ngx.DEBUG, " Try to get cache key \""..key.."\"")

  local cache = ngx.shared.cache
  local value, flags = cache:get(key)
  if value then
    ngx.log(ngx.DEBUG, " Found cache value for key \""..key.."\": "..value)
    value = cjson.decode(value)
  end
  return value, flags
end

function _M.delete(key)
  local cache = ngx.shared.cache
  cache:delete(key)
end

function _M.api_key(host)
  return constants.CACHE.APIS.."/"..host
end

function _M.consumer_key(id)
  return constants.CACHE.CONSUMERS.."/"..id
end

function _M.plugin_configuration_key(name, api_id, consumer_id)
  return constants.CACHE.PLUGINS_CONFIGURATIONS.."/"..name.."/"..api_id..(consumer_id and "/"..consumer_id or "")
end

function _M.basicauth_credential_key(username)
  return constants.CACHE.BASICAUTH_CREDENTIAL.."/"..username
end

function _M.keyauth_credential_key(key)
  return constants.CACHE.KEYAUTH_CREDENTIAL.."/"..key
end

function _M.ssl_data(api_id)
  return constants.CACHE.SSL.."/"..api_id
end

function _M.get_or_set(key, cb)
  local value, err
  -- Try to get
  value = _M.get(key)
  if not value then
    -- Get from closure
    value, err = cb()
    if err then
      return nil, err
    elseif value then
      local ok, err = _M.set(key, val)
      if not ok then
        ngx.log(ngx.ERR, err)
      end
    end
  end
  return value
end

return _M
