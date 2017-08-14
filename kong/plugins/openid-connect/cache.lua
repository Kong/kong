local configuration = require "kong.openid-connect.configuration"
local keys          = require "kong.openid-connect.keys"
local codec         = require "kong.openid-connect.codec"
local timestamp     = require "kong.tools.timestamp"
local utils         = require "kong.tools.utils"
local singletons    = require "kong.singletons"


local concat        = table.concat
local ipairs        = ipairs
local json          = codec.json
local type          = type
local pcall         = pcall
local log           = ngx.log
local encode_base64 = ngx.encode_base64
local sub           = string.sub
local tonumber      = tonumber


local NOTICE        = ngx.NOTICE
local ERR           = ngx.ERR

local cache_get, cache_key
do
  local ok, cache = pcall(require, "kong.tools.database_cache")
  if ok then
    -- 0.10.x
    cache_get = function(key, opts, func, ...)
      local ttl
      if type(opts) == "table" then
        tonumber(opts.ttl)
      else
        ttl = tonumber(opts)
      end
      return cache.get_or_set(key, opts, func, ...)
    end

    cache_key = function(key, entity)
      if entity then
        return entity .. ":" .. key
      end

      return key
    end

  else
    -- 0.11.x
    cache_get = function(key, opts, func, ...)
      local options
      if type(opts) == "number" then
        options = { ttl = opts }
      elseif type(opts) == "table" then
        options = opts
      end
      return singletons.cache:get(key, options, func, ...)
    end

    cache_key = function(key, entity)
      if entity then
        return singletons.dao[entity]:cache_key(key)
      end

      return key
    end
  end
end

local function normalize_issuer(issuer)
  if sub(issuer, -1) == "/" then
    return sub(issuer, 1, #issuer - 1)
  end
  return issuer
end


local issuers = {}


function issuers.init(conf)
  local issuer = normalize_issuer(conf.issuer)

  log(NOTICE, "loading openid connect configuration for ", issuer, " from database")

    local results = singletons.dao.oic_issuers:find_all { issuer = issuer }
  if results and results[1] then
    return {
      issuer        = issuer,
      configuration = results[1].configuration,
      keys          = results[1].keys,
    }
  end

  log(NOTICE, "loading openid connect configuration for ", issuer, " using discovery")

  local opts = {
    http_version = conf.http_version               or 1.1,
    ssl_verify   = conf.ssl_verify == nil and true or conf.ssl_verify,
    timeout      = conf.timeout                    or 10000,
  }

  local claims, err = configuration.load(issuer, opts)
  if not claims then
    log(ERR, "loading openid connect configuration for ", issuer, " using discovery failed with ", err)
    return nil
  end

  local cdec
  cdec, err = json.decode(claims)
  if not cdec then
    log(ERR, err)
    return nil
  end

  local jwks_uri = cdec.jwks_uri
  local jwks
  if jwks_uri then
    log(NOTICE, "loading openid connect jwks from ", jwks_uri)

    jwks, err = keys.load(jwks_uri, opts)
    if not jwks then
      log(ERR, "loading openid connect jwks from ", jwks_uri, " failed with ", err)
      return nil
    end

  elseif cdec.jwks and cdec.jwks.keys then
    jwks, err = json.encode(cdec.jwks.keys)
    if not jwks then
      log(ERR, "unable to encode jwks received as part of the ", issuer, " discovery document (", err , ")")
    end
  end

  local secret = sub(encode_base64(utils.get_rand_bytes(32)), 1, 32)

  local data = {
    issuer        = issuer,
    configuration = claims,
    keys          = jwks,
    secret        = secret,
  }

  data, err = singletons.dao.oic_issuers:insert(data)
  if not data then
    log(ERR, "unable to store issuer ", issuer, " discovery documents in database (", err , ")")
    return nil
  end

  return data
end


function issuers.load(conf)
  local issuer = normalize_issuer(conf.issuer)
  local key    = cache_key(issuer, "oic_issuers")
  return cache_get(key, nil, issuers.init, conf)
end


local consumers = {}


function consumers.init(cons, subject)
  if not subject or subject == "" then
    return nil, "openid connect is unable to load consumer by a missing subject"
  end

  local result, err
  for _, key in ipairs(cons) do
    if key == "id" then
      log(NOTICE, "openid connect is loading consumer by id using " .. subject)
      result, err = singletons.dao.consumers:find { id = subject }
      if type(result) == "table" then
        return result
      end

    else
      log(NOTICE, "openid connect is loading consumer by " .. key .. " using " .. subject)
      result, err = singletons.dao.consumers:find_all { [key] = subject }
      if type(result) == "table" then
        if type(result[1]) == "table" then
          return result[1]
        end
      end
    end
  end
  return nil, err
end


function consumers.load(iss, subject, anon, consumer_by)
  local issuer = normalize_issuer(iss)

  local cons
  if anon then
    cons = { "id" }

  elseif consumer_by then
    cons = consumer_by

  else
    cons = { "custom_id" }
  end

  local key = cache_key(concat{ issuer, "#", subject })
  return cache_get(key, nil, consumers.init, cons, subject)
end


local oauth2 = {}


function oauth2.init(access_token)
  log(NOTICE, "loading kong oauth2 token from database")
  local credentials, err = singletons.dao.oauth2_tokens:find_all { access_token = access_token }

  if err then
    return nil, err
  end

  if #credentials > 0 then
    return credentials[1]
  end

  return credentials
end


function oauth2.load(access_token)
  local key = cache_key(access_token, "oauth2_tokens")
  local token, err = cache_get(key, nil, oauth2.init, access_token)
  if not token then
    return nil, err
  end

  if token.expires_in > 0 then
    local now = timestamp.get_utc()
    if now - token.created_at > (token.expires_in * 1000) then
      return nil, "The access token is invalid or has expired"
    end
  end

  return token
end


local userinfo = {}


function userinfo.init(o, access_token)
  log(NOTICE, "loading user info using access token")
  return o:userinfo(access_token, { userinfo_format = "base64" })
end


function userinfo.load(o, access_token, ttl)
  local key = cache_key(access_token .. "#userinfo")
  return cache_get(key, ttl, userinfo.init, o, access_token)
end


return {
  issuers   = issuers,
  consumers = consumers,
  oauth2    = oauth2,
  userinfo  = userinfo,
}
