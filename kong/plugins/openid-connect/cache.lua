require "kong.plugins.openid-connect.env"


local log           = require "kong.plugins.openid-connect.log"
local configuration = require "kong.openid-connect.configuration"
local keys          = require "kong.openid-connect.keys"
local hash          = require "kong.openid-connect.hash"
local codec         = require "kong.openid-connect.codec"
local utils         = require "kong.tools.utils"
local singletons    = require "kong.singletons"
local http          = require "resty.http"


local concat        = table.concat
local insert        = table.insert
local ipairs        = ipairs
local json          = codec.json
local base64        = codec.base64
local type          = type
local ngx           = ngx
local null          = ngx.null
local time          = ngx.time
local sub           = string.sub
local tonumber      = tonumber
local tostring      = tostring


local function cache_get(key, opts, func, ...)
  local options
  if type(opts) == "number" then
    options = { ttl = opts }

  elseif type(opts) == "table" then
    options = opts
  end

  return singletons.cache:get(key, options, func, ...)
end


local function cache_key(key, entity)
  if not key then
    return nil
  end

  if entity then
    if singletons.dao[entity] then
      return singletons.dao[entity]:cache_key(key)

    elseif singletons.db[entity] then
      return singletons.db[entity]:cache_key(key)
    end
  end

  return key
end


local function cache_invalidate(key)
  return singletons.cache:invalidate(key)
end


local function init_worker()
  if not singletons.worker_events or not singletons.worker_events.register then
    return
  end

  singletons.worker_events.register(function(data)
    log("consumer updated, invalidating cache")

    local old_entity = data.old_entity
    if old_entity then
      if old_entity.custom_id and old_entity.custom_id ~= null and old_entity.custom_id ~= "" then
        cache_invalidate(cache_key("custom_id:" .. old_entity.custom_id, "consumers"))
      end

      if old_entity.username and old_entity.username ~= null and old_entity.username ~= "" then
        cache_invalidate(cache_key("username:" .. old_entity.username,  "consumers"))
      end
    end

    local entity = data.entity
    if entity then
      if entity.custom_id and entity.custom_id ~= null and entity.custom_id ~= "" then
        cache_invalidate(cache_key("custom_id:" .. entity.custom_id, "consumers"))
      end

      if entity.username and entity.username ~= null and entity.username ~= "" then
        cache_invalidate(cache_key("username:" .. entity.username,  "consumers"))
      end
    end
  end, "crud", "consumers")
end


local function normalize_issuer(issuer)
  if sub(issuer, -1) == "/" then
    return sub(issuer, 1, #issuer - 1)
  end

  return issuer
end


local function discover(issuer, opts, now)
  opts = opts or {}

  log.notice("loading configuration for ", issuer, " using discovery")
  local claims, err = configuration.load(issuer, opts)
  if not claims then
    log.err("loading configuration for ", issuer, " using discovery failed with ", err)
    return nil
  end

  local cdec
  cdec, err = json.decode(claims)
  if not cdec then
    log.err("decoding discovery document failed with ", err)
    return nil
  end

  cdec.updated_at = now or time()

  local jwks_uri = cdec.jwks_uri
  local jwks
  if jwks_uri then
    log.notice("loading jwks from ", jwks_uri)

    jwks, err = keys.load(jwks_uri, opts)
    if not jwks then
      log.err("loading jwks from ", jwks_uri, " failed with ", err)
      return nil
    end

    jwks, err = json.decode(jwks)
    if not jwks then
      log.err("decoding jwks failed with ", err)
      return nil
    end

    if jwks.keys then
      jwks = jwks.keys
    end

  elseif type(cdec.jwks) == "table" and cdec.jwks.keys then
    jwks = cdec.jwks.keys
  end

  local extra_jwks_uris = opts.extra_jwks_uris
  if extra_jwks_uris then
    if type(extra_jwks_uris) ~= "table" then
      extra_jwks_uris = { extra_jwks_uris }
    end

    local extra_jwks
    for _, extra_jwks_uri in ipairs(extra_jwks_uris) do
      if type(extra_jwks_uri) ~= "string" then
        log.err("extra jwks uri is not a string (", tostring(extra_jwks_uri) , ")")
        return nil

      else
        log.notice("loading extra jwks from ", extra_jwks_uri)
        extra_jwks, err = keys.load(extra_jwks_uri, opts)
        if not extra_jwks then
          log.err("loading extra jwks from ", extra_jwks_uri, " failed with ", err)
          return nil
        end

        extra_jwks, err = json.decode(extra_jwks)
        if not extra_jwks then
          log.err("decoding extra jwks failed with ", err)
          return nil
        end

        if extra_jwks.keys then
          extra_jwks = extra_jwks.keys
        end

        if not jwks then
          jwks = extra_jwks

        else
          for _, extra_jwk in ipairs(extra_jwks) do
            insert(jwks, extra_jwk)
          end
        end
      end
    end
  end

  if type(jwks) == "table" then
    jwks, err = json.encode(jwks)
    if not jwks then
      log.err("encoding jwks keys failed with ", err)
      return nil
    end
  end

  claims, err = json.encode(cdec)
  if not claims then
    log.err("encoding discovery document failed with ", err)
    return nil
  end

  return claims, jwks
end


local issuers = {}


function issuers.rediscover(issuer, opts)
  opts = opts or {}

  issuer = normalize_issuer(issuer)

  local discovery = singletons.dao.oic_issuers:find_all { issuer = issuer }
  local now = time()

  if discovery and discovery[1] then
    discovery = discovery[1]

    local cdec, err = json.decode(discovery.configuration)
    if not cdec then
      return nil, "decoding discovery document failed with " .. err
    end

    local rediscovery_lifetime = opts.rediscovery_lifetime or 300

    local updated_at = cdec.updated_at or 0
    if now - updated_at < rediscovery_lifetime then
      log.notice("openid connect rediscovery was done in less than 5 mins ago, skipping")
      return discovery.keys
    end
  end

  local claims, jwks = discover(issuer, opts, now)
  if not claims then
    return nil, "openid connect rediscovery failed"
  end

  if discovery then
    local data = {
      configuration = claims,
      keys          = jwks,
    }

    local err
    data, err = singletons.dao.oic_issuers:update({ id = discovery.id }, data)
    if not data then
      log.err("unable to update issuer ", issuer, " discovery documents in database (", err , ")")
      return nil
    end

    return data.keys

  else
    local secret = sub(base64.encode(utils.get_rand_bytes(32)), 1, 32)
    local err
    local data = {
      issuer        = issuer,
      configuration = claims,
      keys          = jwks,
      secret        = secret,
    }

    data, err = singletons.dao.oic_issuers:insert(data)
    if not data then
      log.err("unable to store issuer ", issuer, " discovery documents in database (", err , ")")
      return nil
    end

    return data.keys
  end
end


local function issuers_init(issuer, opts)
  issuer = normalize_issuer(issuer)

  log.notice("loading configuration for ", issuer, " from database")

  local results = singletons.dao.oic_issuers:find_all { issuer = issuer }
  if results and results[1] then
    return {
      issuer        = issuer,
      configuration = results[1].configuration,
      keys          = results[1].keys,
      secret        = results[1].secret,
    }
  end

  local claims, jwks = discover(issuer, opts)
  if not claims then
    return nil, "openid connect discovery failed"
  end

  local secret = sub(base64.encode(utils.get_rand_bytes(32)), 1, 32)

  local data = {
    issuer        = issuer,
    configuration = claims,
    keys          = jwks,
    secret        = secret,
  }

  local err
  data, err = singletons.dao.oic_issuers:insert(data)
  if not data then
    log.err("unable to store issuer ", issuer, " discovery documents in database (", err , ")")
    return nil
  end

  return data
end


function issuers.load(issuer, opts)
  issuer = normalize_issuer(issuer)

  local key = cache_key(issuer, "oic_issuers")
  return cache_get(key, nil, issuers_init, issuer, opts)
end


local consumers = {}


local function consumers_load(subject, key)
  if not subject or subject == "" then
    return nil, "unable to load consumer by a missing subject"
  end

  local result, err

  if key == "id" then
    log.notice("loading consumer by id using ", subject)
    result, err = singletons.dao.consumers:find { id = subject }
    if type(result) == "table" then
      return result
    end

  else
    log.notice("loading consumer by " .. key .. " using " .. subject)
    result, err = singletons.dao.consumers:find_all { [key] = subject }
    if type(result) == "table" and type(result[1]) == "table" then
      return result[1]
    end
  end

  if err then
    log.notice("failed to load consumer (", err, ")")

  else
    log.notice("failed to load consumer")
  end

  return nil, err
end


function consumers.load(subject, anonymous, consumer_by, ttl)
  local cons
  if anonymous then
    cons = { "id" }

  elseif consumer_by then
    cons = consumer_by

  else
    cons = { "custom_id" }
  end

  local err
  for _, field_name in ipairs(cons) do
    local key

    if field_name == "id" then
      key = cache_key(subject, "consumers")

    else
      key = cache_key(field_name .. ":" .. subject, "consumers")
    end

    local consumer
    consumer, err = cache_get(key, ttl, consumers_load, subject, field_name)
    if consumer then
      return consumer
    end
  end

  return nil, err
end


local kong_oauth2 = {}


local function kong_oauth2_credential(credential_id)
  return singletons.dao.oauth2_credentials:find { id = credential_id }
end


local function kong_oauth2_consumer(consumer_id)
  return singletons.dao.consumers:find { id = consumer_id }
end


local function kong_oauth2_load(access_token, now)
  log.notice("loading kong oauth2 token from database")
  local token, err = singletons.dao.oauth2_tokens:find_all { access_token = access_token }
  if not token then
    return nil, err or "unable to load kong oauth2 token from database"
  end

  if #token > 0 then
    token = token[1]
  end

  local expires_in
  if type(token) == "table" then
    expires_in = tonumber(token.expires_in) or 0
  end

  return { now + expires_in, token }, nil, expires_in ~= 0 and expires_in or nil
end


function kong_oauth2.load(ctx, access_token, ttl, use_cache)
  local now = time()
  local key = cache_key(access_token, "oauth2_tokens")
  local res
  local err

  if use_cache then
    res, err = cache_get(key, ttl, kong_oauth2_load, access_token, now)
    if not res then
      return nil, err
    end

    local exp = res[1]
    if now > exp then
      cache_invalidate(key)
      res, err = kong_oauth2_load(access_token, now)
    end

  else
    res, err = kong_oauth2_load(access_token, now)
  end

  if not res then
    return nil, err or "kong oauth was not found"
  end

  local token = res[2]
  if not token.access_token or token.access_token ~= access_token then
    return nil, "kong oauth access token was not found"
  end

  do
    if (token.service_id and ctx.service.id ~= token.service_id) then
      return nil, "kong access token is for different service"

    elseif (token.api_id and ctx.api.id ~= token.api_id) then
      return nil, "kong access token is for different api"
    end
  end

  local expires_in = tonumber(token.expires_in)
  if expires_in and expires_in > 0 then
    local iat = token.created_at / 1000
    if now - iat > expires_in then
      return nil, "kong access token has expired"
    end
  end

  local credential_cache_key = cache_key(token.credential_id, "oauth2_credentials")
  local credential
  credential, err = cache_get(credential_cache_key, ttl, kong_oauth2_credential, token.credential_id)
  if not credential then
    return nil, err
  end

  local consumer_cache_key = cache_key(credential.consumer_id, "consumers")
  local consumer
  consumer, err = cache_get(consumer_cache_key, ttl, kong_oauth2_consumer, credential.consumer_id)
  if not consumer then
    return nil, err
  end

  return token, credential, consumer
end


local introspection = {}


local function introspection_load(oic, access_token, endpoint, hint, headers, now)
  log.notice("introspecting access token with identity provider")
  local token, err = oic.token:introspect(access_token, hint or "access_token", {
    introspection_endpoint = endpoint,
    headers                = headers,
  })
  if not token then
    return nil, err or "unable to introspect token"
  end

  local expires_in
  if type(token) == "table" then
    expires_in = tonumber(token.expires_in)
    if not expires_in then
      local exp = tonumber(token.exp)
      if exp then
        expires_in = exp - now
      end
    end
  end

  if not expires_in then
    expires_in = 0
  end

  return { now + expires_in, token }, nil, expires_in ~= 0 and expires_in or nil
end


function introspection.load(oic, access_token, endpoint, hint, headers, ttl, use_cache)
  if not access_token then
    return nil, "no access token given for token introspection"
  end

  local key = cache_key(base64.encode(hash.S256(concat({
    endpoint or oic.configuration.issuer,
    access_token
  }, "#introspection="))))

  local now = time()
  local res
  local err

  if use_cache and key then
    res, err = cache_get("oic:" .. key, ttl, introspection_load, oic, access_token, endpoint, hint, headers, now)
    if not res then
      return nil, err or "unable to introspect token"
    end

    local exp = res[1]
    if now > exp then
      cache_invalidate("oic:" .. key)
      res, err = introspection_load(oic, access_token, endpoint, hint, headers, now)
    end

  else
    res, err = introspection_load(oic, access_token, endpoint, hint, headers, now)
  end

  if not res then
    return nil, err or "unable to introspect token"
  end

  local token = res[2]
  return token
end


local tokens = {}


local function tokens_load(oic, args, now)
  log.notice("loading tokens from the identity provider")
  local tokens_encoded, err, headers = oic.token:request(args)
  if not tokens_encoded then
    return nil, err
  end

  local expires_in
  if type(tokens_encoded) == "table" then
    expires_in = tonumber(tokens_encoded.expires_in)
    if not expires_in and type(tokens.access_token) == "table" then
      local exp = tonumber(tokens_encoded.access_token.exp)
      if exp then
        expires_in = exp - now
      end
    end
  end

  if not expires_in then
    expires_in = 0
  end

  return { now + expires_in, tokens_encoded, headers }, nil, expires_in ~= 0 and expires_in or nil
end


function tokens.load(oic, args, ttl, use_cache, flush)
  local now = time()
  local iss = oic.configuration.issuer
  local key
  local res
  local err

  if use_cache or flush then
    if args.grant_type == "refresh_token" then
      if not args.refresh_token then
        return nil, "no credentials given for refresh token grant"
      end

      key = cache_key(base64.encode(hash.S256(concat {
        iss,
        "#grant_type=refresh_token&",
        args.refresh_token,
      })))

    elseif args.grant_type == "password" then
      if not args.username or not args.password then
        return nil, "no credentials given for password grant"
      end

      key = cache_key(base64.encode(hash.S256(concat {
        iss,
        "#grant_type=password&",
        args.username,
        "&",
        args.password,
      })))

    elseif args.grant_type == "client_credentials" then
      if not args.client_id or not args.client_secret then
        return nil, "no credentials given for client credentials grant"
      end

      key = cache_key(base64.encode(hash.S256(concat {
        iss,
        "#grant_type=client_credentials&",
        args.client_id,
        "&",
        args.client_secret,
      })))
    end

    if flush and key then
      cache_invalidate("oic:" .. key)
    end
  end

  if use_cache and key then
    res, err = cache_get("oic:" .. key, ttl, tokens_load, oic, args, now)
    if not res then
      return nil, err or "unable to exchange credentials"
    end

    local exp = res[1]
    if now > exp then
      cache_invalidate("oic:" .. key)
      res, err = tokens_load(oic, args, now)
    end

  else
    res, err = tokens_load(oic, args, now)
  end

  if not res then
    return nil, err or "unable to exchange credentials"
  end

  local tokens_encoded = res[2]
  local headers        = res[3]

  return tokens_encoded, nil, headers
end


local token_exchange = {}


local function token_exchange_load(endpoint, opts)
  log.notice("exchanging access token")
  local httpc = http.new()

  if httpc.set_timeouts then
    httpc:set_timeouts(opts.timeout, opts.timeout, opts.timeout)

  else
    httpc:set_timeout(opts.timeout)
  end

  if httpc.set_proxy_options and (opts.http_proxy  or
                                  opts.https_proxy) then
    httpc:set_proxy_options({
      http_proxy                = opts.http_proxy,
      http_proxy_authorization  = opts.http_proxy_authorization,
      https_proxy               = opts.https_proxy,
      https_proxy_authorization = opts.https_proxy_authorization,
      no_proxy                  = opts.no_proxy,
    })
  end

  local res = httpc:request_uri(endpoint, opts)
  if not res then
    local err
    res, err = httpc:request_uri(endpoint, opts)
    if not res then
      httpc:set_keepalive()
      return nil, err
    end
  end

  httpc:set_keepalive()

  local body = res.body
  if sub(body, -1) == "\n" then
    body = sub(body, 1, -2)
  end

  return { body, res.status }
end


function token_exchange.load(access_token, endpoint, opts, ttl, use_cache)
  if not access_token then
    return nil, "no access token given for token exchange"
  end

  if not endpoint then
    return nil, "no token exchange endpoint given for token exchange"
  end

  local key = cache_key(base64.encode(hash.S256(concat({
    endpoint,
    access_token
  }, "#exchange="))))

  local res
  local err

  if use_cache and key then
    res, err = cache_get("oic:" .. key, ttl, token_exchange_load, endpoint, opts)
    if not res then
      return nil, err or "unable to exchange access token"
    end

  else
    res, err = token_exchange_load(endpoint, opts)
  end

  if not res then
    if err then
      return nil, err, 500

    else
      return nil, "unexpected error on token exchange", 500
    end
  end

  local token  = res[1]
  local status = res[2]

  return token, nil, status
end


local userinfo = {}


local function userinfo_load(oic, access_token)
  log.notice("loading user info using access token from identity provider")
  return oic:userinfo(access_token, { userinfo_format = "base64" })
end


function userinfo.load(oic, access_token, ttl, use_cache)
  if not access_token then
    return nil, "no access token given for user info"
  end

  local key = cache_key(base64.encode(hash.S256(concat({
    oic.configuration.issuer,
    access_token
  }, "#userinfo="))))

  if use_cache and key then
    return cache_get("oic:" .. key, ttl, userinfo_load, oic, access_token)

  else
    return userinfo_load(oic, access_token)
  end
end


return {
  init_worker    = init_worker,
  keys           = keys,
  issuers        = issuers,
  consumers      = consumers,
  kong_oauth2    = kong_oauth2,
  introspection  = introspection,
  tokens         = tokens,
  token_exchange = token_exchange,
  userinfo       = userinfo,
  version        = "0.2.6",
}
