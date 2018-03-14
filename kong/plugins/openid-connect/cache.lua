pcall(require, "kong.plugins.openid-connect.env")


local log           = require "kong.plugins.openid-connect.log"
local configuration = require "kong.openid-connect.configuration"
local keys          = require "kong.openid-connect.keys"
local hash          = require "kong.openid-connect.hash"
local codec         = require "kong.openid-connect.codec"
local utils         = require "kong.tools.utils"
local singletons    = require "kong.singletons"
local http          = require "resty.http"


local concat        = table.concat
local ipairs        = ipairs
local json          = codec.json
local base64        = codec.base64
local type          = type
local pcall         = pcall
local ngx           = ngx
local null          = ngx.null
local time          = ngx.time
local sub           = string.sub
local tonumber      = tonumber


local cache_get, cache_key
do
  -- TODO: remove this and 0.10.x support
  local ok, cache = pcall(require, "kong.tools.database_cache")
  if ok then
    -- 0.10.x
    cache_get = function(key, opts, func, ...)
      local ttl
      if type(opts) == "table" then
        ttl = tonumber(opts.ttl)

      else
        ttl = tonumber(opts)
      end

      return cache.get_or_set(key, ttl, func, ...)
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


local function init_worker()
  local cache = singletons.cache
  singletons.worker_events.register(function(data)
    log("consumer updated, invalidating cache")

    local old_entity = data.old_entity
    if old_entity then
      if old_entity.custom_id and old_entity.custom_id ~= null and old_entity.custom_id ~= "" then
        cache:invalidate(cache_key("custom_id:" .. old_entity.custom_id, "consumers"))
      end

      if old_entity.username and old_entity.username ~= null and old_entity.username ~= "" then
        cache:invalidate(cache_key("username:" .. old_entity.username,  "consumers"))
      end
    end

    local entity = data.entity
    if entity then
      if entity.custom_id and entity.custom_id ~= null and entity.custom_id ~= "" then
        cache:invalidate(cache_key("custom_id:" .. entity.custom_id, "consumers"))
      end

      if entity.username and entity.username ~= null and entity.username ~= "" then
        cache:invalidate(cache_key("username:" .. entity.username,  "consumers"))
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


local issuers = {}


function issuers.init(issuer, opts)
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

  log.notice("loading configuration for ", issuer, " using discovery")
  local claims, err = configuration.load(issuer, opts)
  if not claims then
    log.err("loading configuration for ", issuer, " using discovery failed with ", err)
    return nil
  end

  local cdec
  cdec, err = json.decode(claims)
  if not cdec then
    log.err(err)
    return nil
  end

  local jwks_uri = cdec.jwks_uri
  local jwks
  if jwks_uri then
    log.notice("loading jwks from ", jwks_uri)

    jwks, err = keys.load(jwks_uri, opts)
    if not jwks then
      log.err("loading jwks from ", jwks_uri, " failed with ", err)
      return nil
    end

  elseif cdec.jwks and cdec.jwks.keys then
    jwks, err = json.encode(cdec.jwks.keys)
    if not jwks then
      log.err("unable to encode jwks received as part of the ", issuer, "discovery document (", err , ")")
    end
  end

  local secret = sub(base64.encode(utils.get_rand_bytes(32)), 1, 32)

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

  return data
end


function issuers.load(issuer, opts)
  issuer = normalize_issuer(issuer)

  local key = cache_key(issuer, "oic_issuers")
  return cache_get(key, nil, issuers.init, issuer, opts)
end


local consumers = {}


function consumers.init(subject, key)
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

  return nil, err
end


function consumers.load(subject, anon, consumer_by)
  local cons
  if anon then
    cons = { "id" }

  elseif consumer_by then
    cons = consumer_by

  else
    cons = { "custom_id" }
  end

  for _, field_name in ipairs(cons) do
    local key

    if field_name == "id" then
      key = cache_key(subject, "consumers")

    else
      key = cache_key(field_name .. ":" .. subject, "consumers")
    end

    local consumer, err = cache_get(key, nil, consumers.init, subject, field_name)
    if consumer then
      return consumer
    end

    if err then
      log.notice("failed to load consumer (", err, ")")
    end
  end

  return nil
end


local kong_oauth2 = {}


function kong_oauth2.credential(credential_id)
  return singletons.dao.oauth2_credentials:find { id = credential_id }
end


function kong_oauth2.consumer(consumer_id)
  return singletons.dao.consumers:find { id = consumer_id }
end


function kong_oauth2.init(access_token)
  log.notice("loading kong oauth2 token from database")
  local credentials, err = singletons.dao.oauth2_tokens:find_all { access_token = access_token }

  if err then
    return nil, err
  end

  if #credentials > 0 then
    return credentials[1]
  end

  return credentials
end


function kong_oauth2.load(access_token)
  local key = cache_key(access_token, "oauth2_tokens")
  local token, err = cache_get(key, nil, kong_oauth2.init, access_token)
  if not token then
    return nil, err
  end

  if not token.access_token or token.access_token ~= access_token then
    return nil, "kong oauth access token was not found"
  end

  do
    local ctx = ngx.ctx
    if (token.service_id and ctx.service.id ~= token.service_id) then
      return nil, "kong access token is for different service"

    elseif (token.api_id and ctx.api.id ~= token.api_id) then
      return nil, "kong access token is for different api"
    end
  end

  if token.expires_in > 0 then
    local iat = token.created_at / 1000
    local now = time()
    if now - iat > token.expires_in then
      return nil, "kong access token has expired"
    end
  end

  local credential
  local credential_cache_key = cache_key(token.credential_id, "oauth2_credentials")
  credential, err = cache_get(credential_cache_key, nil, kong_oauth2.credential, token.credential_id)

  if not credential then
    return nil, err
  end

  local consumer
  local consumer_cache_key = cache_key(credential.consumer_id, "consumers")
  consumer, err = cache_get(consumer_cache_key, nil, kong_oauth2.consumer, credential.consumer_id)

  if not consumer then
    return nil, err
  end

  return token, credential, consumer
end


local introspection = {}


function introspection.init(o, access_token, endpoint, hint, headers)
  log.notice("introspecting access token with identity provider")
  local token_introspected = o.token:introspect(access_token, hint or "access_token", {
    introspection_endpoint = endpoint,
    headers                = headers,
  })

  local expires_in

  if type(token_introspected) == "table" then
    if token_introspected.expires_in then
      expires_in = tonumber(token_introspected.expires_in)
    end

    if not expires_in then
      if token_introspected.exp then
        local exp = tonumber(token_introspected.exp)
        if exp then
          expires_in = exp - time()
        end
      end
    end
  end

  if expires_in and expires_in < 0 then
    expires_in = nil
  end

  return token_introspected, nil, expires_in
end


function introspection.load(o, access_token, endpoint, hint, headers, ttl)
  local iss = o.configuration.issuer
  local key = cache_key(iss .. "#introspection=" .. access_token)

  return cache_get(key, ttl, introspection.init, o, access_token, endpoint, hint, headers)
end


local tokens = {}


function tokens.init(o, args)
  log.notice("loading tokens from the identity provider")
  local toks, err, headers = o.token:request(args)
  if not toks then
    return nil, err
  end

  local expires_in

  if type(toks) == "table" then
    if toks.expires_in then
      expires_in = tonumber(toks.expires_in)
    end

    if not expires_in then
      if toks.exp then
        local exp = tonumber(toks.exp)
        if exp then
          expires_in = exp - time()
        end
      end
    end
  end

  if expires_in and expires_in < 0 then
    expires_in = nil
  end

  return { toks, headers }, nil, expires_in
end


function tokens.load(o, args, ttl)
  local iss = o.configuration.issuer
  local key

  if args.grant_type == "password" then
    key = cache_key(concat{ iss, "#username=", args.username, "&password=", hash.S256(args.password) })

  elseif args.grant_type == "client_credentials" then
    key = cache_key(concat{ iss, "#client_id=", args.client_id, "&client_secret=", hash.S256(args.client_secret) })

  else
    -- we don't cache authorization code requests
    return o.token:request(args)
  end

  local res, err = cache_get(key, ttl, tokens.init, o, args)

  if not res then
    return nil, err
  end

  return res[1], nil, res[2]
end


local token_exchange = {}


function token_exchange.init(exchange_token_endpoint, opts)
  log.notice("exchanging access token")
  local httpc = http.new()

  if httpc.set_timeouts then
    httpc:set_timeouts(opts.timeout, opts.timeout, opts.timeout)

  else
    httpc:set_timeout(opts.timeout)
  end

  local res = httpc:request_uri(exchange_token_endpoint, opts)
  if not res then
    local err
    res, err = httpc:request_uri(exchange_token_endpoint, opts)
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


function token_exchange.load(o, exchange_token_endpoint, access_token, opts, ttl)
  local res, err

  if ttl then
    local iss = o.configuration.issuer
    local key = cache_key(iss .. "#exchange=" .. access_token)

    res, err = cache_get(key, ttl, token_exchange.init, exchange_token_endpoint, opts)

  else
    res, err = token_exchange.init(exchange_token_endpoint, access_token, opts)
  end

  if not res then
    if err then
      return nil, err, 500

    else
      return nil, "unexpected error on token exchange", 500
    end
  end

  return res[1], nil, res[2]
end


local userinfo = {}


function userinfo.init(o, access_token)
  log.notice("loading user info using access token from identity provider")
  return o:userinfo(access_token, { userinfo_format = "base64" })
end


function userinfo.load(o, access_token, ttl)
  local iss = o.configuration.issuer
  local key = cache_key(iss .. "#userinfo=" .. access_token)

  return cache_get(key, ttl, userinfo.init, o, access_token)
end


return {
  init_worker    = init_worker,
  issuers        = issuers,
  consumers      = consumers,
  kong_oauth2    = kong_oauth2,
  introspection  = introspection,
  tokens         = tokens,
  token_exchange = token_exchange,
  userinfo       = userinfo,
  version        = "0.0.9",
}
