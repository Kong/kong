local configuration = require "kong.openid-connect.configuration"
local keys          = require "kong.openid-connect.keys"
local codec         = require "kong.openid-connect.codec"
local cache         = require "kong.tools.database_cache"
local singletons    = require "kong.singletons"


local json         = codec.json
local log           = ngx.log


local sub           = string.sub


local NOTICE        = ngx.NOTICE
local ERR           = ngx.ERR


local issuers = {}


function issuers.init(conf)
  log(NOTICE, "loading openid connect configuration for ", conf.issuer, " from database")

  local issuer = conf.issuer

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

  local data = {
    issuer        = issuer,
    configuration = claims,
    keys          = jwks,
  }

  data, err = singletons.dao.oic_issuers:insert(data)
  if not data then
    log(ERR, "unable to store issuer ", issuer, " discovery documents in database (", err , ")")
    return nil
  end

  return data
end


function issuers.load(conf)
  local issuer = conf.issuer
  if sub(issuer, -1) == "/" then
      issuer = sub(issuer, 1, #issuer - 1)
  end
  return cache.get_or_set("oic:" .. issuer, conf.ttl, issuers.init, conf)
end


local consumers = {}


function consumers.init(sub)
  local result, err = singletons.dao.consumers:find_all { custom_id = sub }
  if not result then
    return nil, err
  end
  return result[1]
end


function consumers.load(conf, sub)
  return cache.get_or_set(conf.issuer .. "#" .. sub, conf.ttl, consumers.init, sub)
end


local revoked = {}


function revoked.load()
end


return {
  issuers   = issuers,
  consumers = consumers,
  revoked   = revoked,
}
