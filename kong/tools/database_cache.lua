local resty_lock = require "resty.lock"
local json_encode = require("cjson.safe").encode
local json_decode = require("cjson.safe").decode
local cache = ngx.shared.cache
local ngx_log = ngx.log
local gettime = ngx.now

local TTL_EXPIRE_KEY = "___expire_ttl"

local CACHE_KEYS = {
  APIS = "apis",
  CONSUMERS = "consumers",
  PLUGINS = "plugins",
  CERTIFICATES = "certificates",
  BASICAUTH_CREDENTIAL = "basicauth_credentials",
  HMACAUTH_CREDENTIAL = "hmacauth_credentials",
  KEYAUTH_CREDENTIAL = "keyauth_credentials",
  OAUTH2_CREDENTIAL = "oauth2_credentials",
  JWTAUTH_CREDENTIAL = "jwtauth_credentials",
  OAUTH2_TOKEN = "oauth2_token",
  ACLS = "acls",
  SSL = "ssl",
  ALL_APIS_BY_DIC = "ALL_APIS_BY_DIC",
  LDAP_CREDENTIAL = "ldap_credentials",
  BOT_DETECTION = "bot_detection",
  UPSTREAMS = "upstreams",
  TARGETS = "targets",
}

local _M = {}

-- Shared Dictionary

function _M.sh_set(key, value, exptime)
  return cache:set(key, value, exptime or 0)
end

function _M.sh_add(key, value, exptime)
  return cache:add(key, value, exptime)
end

function _M.sh_incr(key, value, init)
  return cache:incr(key, value, init)
end

function _M.sh_get(key)
  return cache:get(key)
end

function _M.sh_delete(key)
  cache:delete(key)
end

function _M.sh_delete_all()
  cache:flush_all() -- This does not free up the memory, only marks the items as expired
  cache:flush_expired() -- This does actually remove the elements from the memory
end

-- Local Memory

local DATA = {}

function _M.set(key, value, exptime)
  exptime = exptime or 0

  if exptime ~= 0 then
    value = {
      value = value,
      [TTL_EXPIRE_KEY] = gettime() + exptime,
    }
  end

  DATA[key] = value

  -- Save into Shared Dictionary
  local _, err = _M.sh_set(key, json_encode(value), exptime)
  if err then return nil, err end

  return true
end

function _M.get(key)
  local now = gettime()

  -- check local memory, and verify ttl
  local value = DATA[key]
  if value ~= nil then
    if type(value) ~= "table" or not value[TTL_EXPIRE_KEY] then
      -- found non-ttl value, just return it
      return value
    elseif value[TTL_EXPIRE_KEY] >= now then
      -- found ttl-based value, within ttl
      return value.value
    end
    -- value with expired ttl, delete it
    DATA[key] = nil
  end

  -- nothing found yet, get it from Shared Dictionary
  value = _M.sh_get(key)
  if value == nil then
    -- nothing found
    return nil
  end
  value = json_decode(value)
  DATA[key] = value  -- store in memory, so we don't need to deserialize next time

  if type(value) ~= "table" or not value[TTL_EXPIRE_KEY] then
    -- found non-ttl value, just return it
    return value
  end
  -- found ttl-based value, no need to check ttl, we assume shm did that,
  -- worst-case on next request it will immediately be expired again
  return value.value
end

function _M.delete(key)
  DATA[key] = nil
  _M.sh_delete(key)
end

function _M.delete_all()
  DATA = {}
  _M.sh_delete_all()
end

-- Retrieves a piece of data from the cache or loads it.
-- **IMPORTANT:** the callback function may not exit the request early by e.g.
-- sending a 404 response from the callback. The callback will be nested inside
-- lock/unlock calls, and hence it MUST return or the lock will not be
-- unlocked. Which in turn will lead to deadlocks and timeouts. 
-- @param key the key under which to retrieve the data from the cache
-- @param ttl time-to-live for the entry (in seconds)
-- @param cb callback function. If no data is found under `key`, then the callback
-- is called with the additional parameters. The result from the callback is
-- then stored in the cache, and returned.
-- @param ... the additional parameters passed to `cb`
-- @return the (newly) cached value
function _M.get_or_set(key, ttl, cb, ...)

  -- Try to get the value from the cache
  local value = _M.get(key)
  if value ~= nil then return value end

  local lock, err = resty_lock:new("cache_locks", {
    exptime = 10,
    timeout = 5
  })
  if not lock then
    ngx_log(ngx.ERR, "could not create lock: ", err)
    return
  end

  -- The value is missing, acquire a lock
  local elapsed, err = lock:lock(key)
  if not elapsed then
    ngx_log(ngx.ERR, "failed to acquire cache lock: ", err)
    return
  end

  -- Lock acquired. Since in the meantime another worker may have
  -- populated the value we have to check again
  value = _M.get(key)
  if value == nil then
    -- Get from closure
    value, err = cb(...)
    if err then
      return nil, err
    end

    if value ~= nil then
      local ok, err = _M.set(key, value, ttl)
      if not ok then
        ngx_log(ngx.ERR, err)
        return
      end
    end
  end

  local ok, err = lock:unlock()
  if not ok and err then
    ngx_log(ngx.ERR, "failed to unlock: ", err)
  end

  return value
end

-- Utility Functions

function _M.api_key(host)
  return CACHE_KEYS.APIS..":"..host
end

function _M.consumer_key(id)
  return CACHE_KEYS.CONSUMERS..":"..id
end

function _M.plugin_key(name, api_id, consumer_id)
  return CACHE_KEYS.PLUGINS..":"..name..(api_id and ":"..api_id or "")..(consumer_id and ":"..consumer_id or "")
end

function _M.certificate_key(sni)
  return CACHE_KEYS.CERTIFICATES .. ":" .. sni
end

function _M.basicauth_credential_key(username)
  return CACHE_KEYS.BASICAUTH_CREDENTIAL..":"..username
end

function _M.oauth2_credential_key(client_id)
  return CACHE_KEYS.OAUTH2_CREDENTIAL..":"..client_id
end

function _M.oauth2_token_key(access_token)
  return CACHE_KEYS.OAUTH2_TOKEN..":"..access_token
end

function _M.keyauth_credential_key(key)
  return CACHE_KEYS.KEYAUTH_CREDENTIAL..":"..key
end

function _M.hmacauth_credential_key(username)
  return CACHE_KEYS.HMACAUTH_CREDENTIAL..":"..username
end

function _M.jwtauth_credential_key(secret)
  return CACHE_KEYS.JWTAUTH_CREDENTIAL..":"..secret
end

function _M.ldap_credential_key(api_id, username)
  return CACHE_KEYS.LDAP_CREDENTIAL.."_"..api_id..":"..username
end

function _M.acls_key(consumer_id)
  return CACHE_KEYS.ACLS..":"..consumer_id
end

function _M.ssl_data(api_id)
  return CACHE_KEYS.SSL..(api_id and ":"..api_id or "")
end

function _M.bot_detection_key(key)
  return CACHE_KEYS.BOT_DETECTION..":"..key
end

function _M.upstreams_dict_key()
  return CACHE_KEYS.UPSTREAMS
end

function _M.upstream_key(upstream_id)
  return CACHE_KEYS.UPSTREAMS..":"..upstream_id
end

function _M.targets_key(upstream_id)
  return CACHE_KEYS.TARGETS..":"..upstream_id
end

function _M.all_apis_by_dict_key()
  return CACHE_KEYS.ALL_APIS_BY_DIC
end

return _M
