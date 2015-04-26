local cjson = require "cjson"
local constants = require "kong.constants"

local _M = {}

function _M.set(key, value, exptime)
  if exptime == nil then
    exptime = configuration and configuration.database_cache_expiration or 0
  end

  local cache = ngx.shared.cache
  if value then
    value = cjson.encode(value)
  end
  if ngx then
    ngx.log(ngx.DEBUG, " saving cache key \""..key.."\": "..value)
  end
  local succ, err, forcible = cache:set(key, value, exptime)
  return succ, err, forcible
end

function _M.get(key)
  if ngx then
    ngx.log(ngx.DEBUG, " Try to get cache key \""..key.."\"")
  end

  local cache = ngx.shared.cache
  local value, flags = cache:get(key)
  if value then
    if ngx then
      ngx.log(ngx.DEBUG, " Found cache value for key \""..key.."\": "..value)
    end
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

function _M.plugin_configuration_key(name, api_id, consumer_id)
  return constants.CACHE.PLUGINS_CONFIGURATIONS.."/"..name.."/"..api_id..(consumer_id and "/"..consumer_id or "")
end

function _M.basicauth_credential_key(username)
  return constants.CACHE.BASICAUTH_CREDENTIAL.."/"..username
end

function _M.keyauth_credential_key(key)
  return constants.CACHE.KEYAUTH_CREDENTIAL.."/"..key
end

function _M.get_and_set(key, cb)
  local val = _M.get(key)
  if not val then
    val = cb()
    if val then
      local succ, err = _M.set(key, val)
      if not succ and ngx then
        ngx.log(ngx.ERR, err)
      end
    end
  end
  return val
end

return _M
