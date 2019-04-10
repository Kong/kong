require "kong.plugins.openid-connect.env"


local log           = require "kong.plugins.openid-connect.log"
local configuration = require "kong.openid-connect.configuration"
local keys          = require "kong.openid-connect.keys"
local hash          = require "kong.openid-connect.hash"
local codec         = require "kong.openid-connect.codec"
local utils         = require "kong.tools.utils"
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
local kong          = kong


local function cache_get(key, opts, func, ...)
  local options
  if type(opts) == "number" then
    options = { ttl = opts }

  elseif type(opts) == "table" then
    options = opts
  end

  return kong.cache:get(key, options, func, ...)
end


local function cache_key(key, entity)
  if not key then
    return nil
  end

  if entity then
    return kong.db[entity]:cache_key(key)
  end

  return key
end


local function cache_invalidate(key)
  return kong.cache:invalidate(key)
end


local function get_expiry_and_cache_ttl(token, ttl)
  local expires_in
  if type(token) == "table" then
    if token.expires_in then
      expires_in = tonumber(token.expires_in)
    end

    if not expires_in then
      if token.exp then
        local exp = tonumber(token.exp)
        if exp then
          if exp == 0 then
            expires_in = 0
          else
            expires_in = exp - ttl.now
          end
        end
      end
    end
  end

  local exp
  local cache_ttl
  if not expires_in or expires_in < 0 then
    exp = 0
    cache_ttl = ttl.ttl

  elseif expires_in == 0 then
    exp = 0
    if ttl.max_ttl and ttl.max_ttl > 0 then
      cache_ttl = ttl.max_ttl
    else
      cache_ttl = 0
    end

  else
    exp = ttl.now + expires_in

    if ttl.max_ttl and ttl.max_ttl > 0 and expires_in > ttl.max_ttl then
      cache_ttl = ttl.max_ttl
    elseif ttl.min_ttl and ttl.min_ttl > 0 and expires_in < ttl.min_ttl then
      cache_ttl = ttl.min_ttl
    else
      cache_ttl = expires_in
    end
  end

  return exp, cache_ttl
end


local function get_secret()
  return sub(base64.encode(utils.get_rand_bytes(32)), 1, 32)
end


local function init_worker()
  if not kong.worker_events or not kong.worker_events.register then
    return
  end

  kong.worker_events.register(function(data)
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

  local cdec

  log.notice("loading configuration for ", issuer, " using discovery")
  local claims, err = configuration.load(issuer, opts)
  if not claims then
    log.notice("loading configuration for ", issuer, " using discovery failed with ", err ,
               " (falling back to empty configuration)")
    cdec = {
      issuer = issuer,
    }

  else
    cdec, err = json.decode(claims)
    if not cdec then
      log.err("decoding discovery document failed with ", err)
      return nil
    end
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

  if not jwks then
    jwks = {}
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

  local discovery = kong.db.oic_issuers:select_by_issuer(issuer)
  local now = time()

  if discovery then
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
    data, err = kong.db.oic_issuers:update({ id = discovery.id }, data)
    if not data then
      log.err("unable to update issuer ", issuer, " discovery documents in database (", err , ")")
      return nil
    end

    return data.keys

  else
    local secret = get_secret()
    local err
    local data = {
      issuer        = issuer,
      configuration = claims,
      keys          = jwks,
      secret        = secret,
    }

    data, err = kong.db.oic_issuers:insert(data)
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

  local results = kong.db.oic_issuers:select_by_issuer(issuer)
  if results then
    return {
      issuer        = issuer,
      configuration = results.configuration,
      keys          = results.keys,
      secret        = results.secret,
    }
  end

  local claims, jwks = discover(issuer, opts)
  if not claims then
    return nil, "openid connect discovery failed"
  end

  local secret = get_secret()

  local data = {
    issuer        = issuer,
    configuration = claims,
    keys          = jwks,
    secret        = secret,
  }

  local err
  data, err = kong.db.oic_issuers:insert(data)
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

  log.notice("loading consumer by ", key, " using ", subject)

  if key == "id" then
    if utils.is_valid_uuid(subject) then
      result, err = kong.db.consumers:select({ id = subject })
    end

  elseif key == "username" then
    result, err = kong.db.consumers:select_by_username(subject)
  elseif key == "custom_id" then
    result, err = kong.db.consumers:select_by_custom_id(subject)
  else
    return nil, "consumer cannot be loaded by " .. key
  end

  if type(result) == "table" then
    return result
  end

  if err then
    log.notice("failed to load consumer by ", key, " (", err, ")")
  else
    log.notice("failed to load consumer by ", key)
  end

  return nil, err
end


function consumers.load(subject, anonymous, consumer_by, ttl)
  local field_names
  if anonymous then
    field_names = { "id" }

  elseif consumer_by then
    field_names = consumer_by

  else
    field_names = { "custom_id" }
  end

  local err
  for _, field_name in ipairs(field_names) do
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


local function kong_oauth2_credential(credential)
  return kong.db.oauth2_credentials:select(credential)
end


local function kong_oauth2_consumer(consumer)
  return kong.db.consumers:select(consumer)
end


local function kong_oauth2_load(access_token, ttl)
  log.notice("loading kong oauth2 token from database")
  local token, err = kong.db.oauth2_tokens:select_by_access_token(access_token)

  if err then
    return nil, err
  end

  if not token then
    return nil, "unable to load kong oauth2 token from database"
  end

  local _, cache_ttl = get_expiry_and_cache_ttl(token, ttl)

  return token, nil, cache_ttl
end


function kong_oauth2.load(ctx, access_token, ttl, use_cache)
  local key = cache_key(access_token, "oauth2_tokens")
  local token
  local err

  if use_cache then
    token, err = cache_get(key, ttl, kong_oauth2_load, access_token, ttl)
    if not token then
      return nil, err
    end

    local exp = get_expiry_and_cache_ttl(token, ttl)
    if exp ~= 0 and exp < ttl.now then
      cache_invalidate(key)
      token, err = kong_oauth2_load(access_token, ttl)
    end

  else
    token, err = kong_oauth2_load(access_token, ttl)
  end

  if not token then
    return nil, err or "kong oauth was not found"
  end

  if not token.access_token or token.access_token ~= access_token then
    return nil, "kong oauth access token was not found"
  end

  if token.service and ctx.service and ctx.service.id ~= token.service.id then
    return nil, "kong access token is for different service"
  end

  local ttl_new
  local exp = get_expiry_and_cache_ttl(token, ttl)
  if exp > 0 then
    local iat = token.created_at
    if (ttl.now - iat) > (exp - ttl.now) then
      return nil, "kong access token has expired"
    end

    local token_ttl = exp - ttl.now
    if token_ttl > 0 then
      if ttl.max_ttl and ttl.max_ttl > 0 then
        if token_ttl > ttl.max_ttl then
          token_ttl = ttl.max_ttl
        end
      end

      if ttl.min_ttl and ttl.min_ttl > 0 then
        if token_ttl < ttl.min_ttl then
          token_ttl = ttl.min_ttl
        end
      end

      ttl_new = {
        ttl = token_ttl,
        neg_ttl = ttl.neg_ttl,
        resurrect_ttl = ttl.resurrect_ttl,
      }

    else
      ttl_new = ttl
    end

  else
    ttl_new = ttl
  end

  local credential_cache_key = cache_key(token.credential, "oauth2_credentials")
  local credential
  credential, err = cache_get(credential_cache_key, ttl_new, kong_oauth2_credential, token.credential)
  if not credential then
    return nil, err
  end

  local consumer_cache_key = cache_key(credential.consumer, "consumers")
  local consumer
  consumer, err = cache_get(consumer_cache_key, ttl_new, kong_oauth2_consumer, credential.consumer)
  if not consumer then
    return nil, err
  end

  return token, credential, consumer
end


local introspection = {}


local function introspection_load(oic, access_token, endpoint, hint, headers, args, ttl)
  log.notice("introspecting access token with identity provider")
  local token, err = oic.token:introspect(access_token, hint or "access_token", {
    introspection_endpoint = endpoint,
    headers                = headers,
    args                   = args,
  })
  if not token then
    return nil, err or "unable to introspect token"
  end

  local exp, cache_ttl = get_expiry_and_cache_ttl(token, ttl)

  return { exp, token }, nil, cache_ttl
end


function introspection.load(oic, access_token, endpoint, hint, headers, args, ttl, use_cache)
  if not access_token then
    return nil, "no access token given for token introspection"
  end

  local key = cache_key(base64.encode(hash.S256(concat({
    endpoint or oic.configuration.issuer,
    access_token
  }, "#introspection="))))

  local res
  local err

  if use_cache and key then
    res, err = cache_get("oic:" .. key, ttl, introspection_load, oic, access_token, endpoint, hint, headers, args, ttl)
    if not res then
      return nil, err or "unable to introspect token"
    end

    local exp = res[1]
    if exp > 0 and exp < ttl.now then
      cache_invalidate("oic:" .. key)
      res, err = introspection_load(oic, access_token, endpoint, hint, headers, args, ttl)
    end

  else
    res, err = introspection_load(oic, access_token, endpoint, hint, headers, args, ttl)
  end

  if not res then
    return nil, err or "unable to introspect token"
  end

  local token = res[2]
  return token
end


local tokens = {}


local function tokens_load(oic, args, ttl)
  log.notice("loading tokens from the identity provider")
  local tokens_encoded, err, headers = oic.token:request(args)
  if not tokens_encoded then
    return nil, err
  end

  local exp, cache_ttl = get_expiry_and_cache_ttl(tokens_encoded, ttl)

  return { exp, tokens_encoded, headers }, nil, cache_ttl
end


function tokens.load(oic, args, ttl, use_cache, flush)
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
    res, err = cache_get("oic:" .. key, ttl, tokens_load, oic, args, ttl)
    if not res then
      return nil, err or "unable to exchange credentials"
    end

    local exp = res[1]
    if exp < ttl.now then
      cache_invalidate("oic:" .. key)
      res, err = tokens_load(oic, args, ttl)
    end

  else
    res, err = tokens_load(oic, args, ttl)
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
  return oic:userinfo(access_token)
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
  version        = "1.2.0",
}
