-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log           = require "kong.plugins.openid-connect.log"
local configuration = require "kong.openid-connect.configuration"
local keys          = require "kong.openid-connect.keys"
local utils         = require "kong.tools.utils"
local sha256        = require "kong.tools.sha256"
local http          = require "resty.http"
local json          = require "cjson.safe"
local workspaces    = require "kong.workspaces"
local semaphore     = require "ngx.semaphore"
local string_buffer = require("string.buffer")


local setmetatable  = setmetatable
local concat        = table.concat
local insert        = table.insert
local sort          = table.sort
local ipairs        = ipairs
local pairs         = pairs
local encode_base64 = ngx.encode_base64
local type          = type
local ngx           = ngx
local null          = ngx.null
local time          = ngx.time
local sub           = string.sub
local find          = string.find
local fmt           = string.format
local tonumber      = tonumber
local spawn         = ngx.thread.spawn
local wait          = ngx.thread.wait
local kong          = kong
local url_encode    = ngx.escape_uri


local TOKEN_DECODE_OPTS = {
  verify_signature = false,
  verify_claims    = false,
}


local TOKEN_DECODE_SIGNATURE_OPTS = {
  verify_signature = true,
  verify_claims    = false,
}


local sha256_base64url do
  if sha256.sha256_base64url then
    sha256_base64url = sha256.sha256_base64url

  else
    local S256 = require("kong.openid-connect.hash").S256
    local encode_base64url = require("ngx.base64").encode_base64url
    sha256_base64url = function(key)
      return encode_base64url(S256(key))
    end
  end
end


local rediscovery_semaphores = {}


local discovery_data = { n = 0 }
local jwks_cache = {}


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
  return kong.cache:invalidate_local(key)
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
  if not expires_in then
    exp = 0
    cache_ttl = ttl.default_ttl

  elseif expires_in < 0 then
    exp = ttl.now + expires_in

    if ttl.min_ttl and ttl.min_ttl > 0 and expires_in < ttl.min_ttl then
      cache_ttl = ttl.min_ttl
    else
      cache_ttl = ttl.default_ttl
    end

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
  return encode_base64(utils.get_rand_bytes(24), true)
end


local function cache_issuer(discovery)
  return discovery
end


local function parse_jwt_response(oic, body, headers, ignore_signature, hint)
  local token, jwt
  if type(headers) == "table" then
    local content_type = headers["Content-Type"]
    if type(content_type) == "string" then
      if find(content_type, "application/jwt", 1, true) == 1 or
         find(content_type, hint, 1, true) == 1
      then
        local decoded, err = oic.token:decode(body, ignore_signature and TOKEN_DECODE_OPTS
                                                                      or TOKEN_DECODE_SIGNATURE_OPTS)
        if not decoded then
          if err then
            return nil, "unable to decode jwt response (" .. err .. ")"
          end

          return nil, "unable to decode jwt response"
        end

        if type(decoded) ~= "table" then
          return nil, "invalid jwt response received"
        end

        if type(decoded.payload) ~= "table" then
          return nil, "invalid jwt response payload received"
        end

        token = decoded.payload
        jwt = body

        if hint == "application/token-introspection+jwt" and type(token.token_introspection) == "table" then
          token = token.token_introspection
        end

        log("jwt response received")
      end
    end
  end

  if not token then
    local err
    token, err = json.decode(body)
    if not token then
      if type(body) == "table" then
        token = body -- backward compatibility with older version of Kong OpenID Connect library

      else
        if err then
          return nil, "unable to decode json response (" .. err .. ")"
        end

        return nil, "unable to decode json response"
      end
    end

    if type(token) ~= "table" then
      return nil, "invalid json response received"
    end

    log("json response received")
  end

  return token, nil, jwt
end


local function init_worker()
  if kong.db and kong.db.oic_issuers and ngx.worker.id() == 0 then
    for issuer_entity, err in kong.db.oic_issuers:each() do
      if err then
        log.warn("warmup of issuer cache failed with: ", err)
        break
      end

      local key = cache_key(issuer_entity.issuer, "oic_issuers")
      cache_get(key, nil, cache_issuer, issuer_entity)
    end
  end

  if not (kong.worker_events and kong.worker_events.register) then
    return
  end

  if kong.configuration.database == "off" then
    local remove = table.remove
    kong.worker_events.register(function()
      if discovery_data and discovery_data.n > 0 then
        for i = discovery_data.n, 1, -1 do
          local key = cache_key(discovery_data[i].issuer, "oic_issuers")
          cache_invalidate(key)
        end

        discovery_data = { n = 0 }
      end
    end, "openid-connect", "purge-discovery")
    kong.worker_events.register(function(issuer)
      local data = discovery_data[issuer]
      if data then
        if discovery_data and discovery_data.n > 0 then
          for i = discovery_data.n, 1, -1 do
            if discovery_data[i].id == data.id then
              remove(discovery_data, i)
              discovery_data.n = discovery_data.n - 1
              break
            end
          end
          discovery_data[data.id] = nil
          discovery_data[data.issuer] = nil

          local key = cache_key(data.issuer, "oic_issuers")
          cache_invalidate(key)
        end
      end
    end, "openid-connect", "delete-discovery")

  else
    kong.worker_events.register(function(data)
      workspaces.set_workspace(data.workspace)
      local operation = data.operation
      log("consumer ", operation or "update", "d, invalidating cache")

      local old_entity = data.old_entity
      local old_username
      local old_custom_id
      if old_entity then
        old_custom_id = old_entity.custom_id
        if old_custom_id and old_custom_id ~= null and old_custom_id ~= "" then
          kong.cache:invalidate(kong.db.consumers:cache_key("custom_id", old_custom_id))
        end

        old_username = old_entity.username
        if old_username and old_username ~= null and old_username ~= "" then
          kong.cache:invalidate(kong.db.consumers:cache_key("username", old_username))
          kong.cache:invalidate(kong.db.consumers:cache_key("username_lower", old_username))
        end
      end

      local entity = data.entity
      if entity then
        local custom_id = entity.custom_id
        if custom_id and custom_id ~= null and custom_id ~= "" and custom_id ~= old_custom_id then
          kong.cache:invalidate(kong.db.consumers:cache_key("custom_id", custom_id))
        end

        local username = entity.username
        if username and username ~= null and username ~= "" and username ~= old_username then
          kong.cache:invalidate(kong.db.consumers:cache_key("username", username))
          kong.cache:invalidate(kong.db.consumers:cache_key("username_lower", username))
        end
      end
    end, "crud", "consumers")

    kong.worker_events.register(function(data)
      workspaces.set_workspace(data.workspace)
      local operation = data.operation
      log("issuer ", operation or "update", "d, invalidating cache")

      local old_issuer
      local old_entity = data.old_entity
      if old_entity then
        old_issuer = old_entity.issuer
        kong.cache:invalidate(cache_key(old_issuer, "oic_issuers"))
      end

      local entity = data.entity
      if entity and entity.issuer ~= old_issuer then
        kong.cache:invalidate(cache_key(entity.issuer, "oic_issuers"))
      end
    end, "crud", "oic_issuers")
  end
end


local function normalize_issuer(issuer)
  if sub(issuer, -1) == "/" then
    return sub(issuer, 1, -2)
  end

  return issuer
end


local function load_configuration(issuer, opts)
  local conf, err = configuration.load(issuer, opts)
  if not conf then
    return nil, err
  end

  return {
    updated_at = time(),
    conf = conf,
  }
end


local function fetch_configuration(issuer, opts)
  local key = "oic:" .. sha256_base64url(issuer .. "#configuration")
  local data, err = cache_get(key, nil, load_configuration, issuer, opts)
  if not data then
    return nil, err
  end

  local rediscovery_lifetime = opts.rediscovery_lifetime or 30
  local updated_at = data.updated_at or 0
  local seconds_since_last_rediscovery = time() - updated_at
  if seconds_since_last_rediscovery < rediscovery_lifetime then
    log.notice("rediscovery for ", issuer, " was done recently (",
               rediscovery_lifetime - seconds_since_last_rediscovery,
               " seconds until next rediscovery)")
    return data.conf
  end

  cache_invalidate(key)
  data, err = cache_get(key, nil, load_configuration, issuer, opts)
  if not data then
    return nil, err
  end

  return data.conf
end


local function load_keys(jwks_uri, opts)
  local jwks, err = keys.load(jwks_uri, opts)
  if not jwks then
    return nil, err
  end

  return {
    updated_at = time(),
    jwks = jwks,
  }
end


local function fetch_keys(jwks_uri, opts)
  local key = "oic:" .. sha256_base64url(jwks_uri .. "#jwks")
  local data, err = cache_get(key, nil, load_keys, jwks_uri, opts)
  if not data then
    return nil, err
  end

  local rediscovery_lifetime = opts.rediscovery_lifetime or 30
  local updated_at = data.updated_at or 0
  local seconds_since_last_rediscovery = time() - updated_at
  if seconds_since_last_rediscovery < rediscovery_lifetime then
    log.notice("rediscovery for ", jwks_uri, " was done recently (",
               rediscovery_lifetime - seconds_since_last_rediscovery,
               " seconds until next rediscovery)")
    return data.jwks
  end

  cache_invalidate(key)
  data, err = cache_get(key, nil, load_keys, jwks_uri, opts)
  if not data then
    return nil, err
  end

  return data.jwks
end


local function decode_previous_configuration(issuer_entity, issuer)
  local configuration_decoded, err = json.decode(issuer_entity.configuration)
  if type(configuration_decoded) ~= "table" then
    log.err("decoding previous discovery document failed: ", err or "unknown error",
               " (falling back to empty configuration)")
    return {
      issuer = issuer,
    }
  end

  return configuration_decoded
end


local function decode_previous_jwks(jwks_uri, jwks_string, err)
  if jwks_cache[jwks_uri] then
    log.notice("loading jwks from ", jwks_uri, " thread failed: ", jwks_string or "unknown error",
               " (falling back to previous jwks)")
    local jwks_uri_jwks
    jwks_uri_jwks, err = json.decode(jwks_cache[jwks_uri])
    if type(jwks_uri_jwks) ~= "table" then
      log.notice("decoding previous jwks failed: ", err or "type error")
      return
    end

    return jwks_uri_jwks
  end

  log.notice("loading jwks from ", jwks_uri, " failed: ", err or "unknown error",
             " (ignoring)")
end

local function config_fallback(issuer_entity, issuer)
  if issuer_entity then
    log.debug("falling back to previous configuration")
    return decode_previous_configuration(issuer_entity, issuer)

  else
    log.debug("falling back to empty configuration")
    return {
      issuer = issuer,
    }
  end
end

local function get_config(issuer, opts)
  local conf, decoded, err
  conf, err = fetch_configuration(issuer, opts)
  if type(conf) ~= "string" then
    log.notice("loading configuration for ", issuer, " using discovery failed: ", err or "unknown error")
    return
  end

  decoded, err = json.decode(conf)
  if type(decoded) ~= "table" then
    log.err("decoding discovery document failed: ", err or "unknown error")
    return
  end

  return decoded
end


local function discover(issuer, opts, issuer_entity)
  opts = opts or {}

  local configuration_decoded, err

  log.notice("loading configuration for ", issuer, " using discovery")

  if not opts.using_pseudo_issuer then
    configuration_decoded = get_config(issuer, opts)
  end

  if not configuration_decoded then
    configuration_decoded = config_fallback(issuer_entity, issuer)
  end

  local jwks = setmetatable({}, json.array_mt)
  local jwk_count = 0
  local configuration_jwks = configuration_decoded.jwks
  if type(configuration_jwks) == "table" then
    if type(configuration_jwks.keys) == "table" then
      configuration_jwks = configuration_jwks.keys
    end

    for _, jwk in ipairs(configuration_jwks) do
      jwk_count = jwk_count + 1
      jwks[jwk_count] = jwk
    end
  end

  local jwks_uris_count = 0
  local jwks_uris = {}
  local jwks_uri = configuration_decoded.jwks_uri
  if type(jwks_uri) == "string" then
    jwks_uris_count = jwks_uris_count + 1
    jwks_uris[jwks_uris_count] = jwks_uri
    jwks_uris[jwks_uri] = true
  end

  local extra_jwks_uris = opts.extra_jwks_uris
  if extra_jwks_uris then
    if type(extra_jwks_uris) ~= "table" then
      extra_jwks_uris = { extra_jwks_uris }
    end

    for _, extra_jwks_uri in ipairs(extra_jwks_uris) do
      if type(extra_jwks_uri) == "string" and not jwks_uris[extra_jwks_uri] then
        jwks_uris_count = jwks_uris_count + 1
        jwks_uris[jwks_uris_count] = extra_jwks_uri
        jwks_uris[extra_jwks_uri] = true
      end
    end
  end

  if jwks_uris_count > 0 then
    local threads = kong.table.new(jwks_uris_count, 0)
    for i = 1, jwks_uris_count do
      log.notice("loading jwks from ", jwks_uris[i])
      threads[i] = spawn(fetch_keys, jwks_uris[i], opts)
    end
    local jwks_string, ok
    for i = 1, jwks_uris_count do
      local jwks_uri_jwks
      jwks_uri = jwks_uris[i]
      ok, jwks_string, err = wait(threads[i])
      if not ok then
        jwks_uri_jwks = decode_previous_jwks(jwks_uri, jwks_string, err)

      else
        if type(jwks_string) ~= "string" then
          jwks_uri_jwks = decode_previous_jwks(jwks_uri, jwks_string, err)

        else
          jwks_uri_jwks, err = json.decode(jwks_string)
          if type(jwks_uri_jwks) == "table" then
            jwks_cache[jwks_uri] = jwks_string

          else
            if jwks_cache[jwks_uri] then
              log.notice("decoding jwks failed: ", err or "type error (falling back to previous jwks)")
              jwks_uri_jwks, err = json.decode(jwks_cache[jwks_uri])
              if type(jwks_uri_jwks) ~= "table" then
                log.notice("decoding previous jwks failed: ", err or "type error")
              end

            else
              log.notice("decoding jwks failed: ", err or "type error (ignoring)")
            end
          end
        end
      end

      if type(jwks_uri_jwks) == "table" then
        if type(jwks_uri_jwks.keys) == "table" then
          jwks_uri_jwks = jwks_uri_jwks.keys
        end

        for _, jwk in ipairs(jwks_uri_jwks) do
          jwk_count = jwk_count + 1
          jwks[jwk_count] = jwk
        end
      end
    end
  end

  if jwk_count > 0 then
    jwks, err = json.encode(jwks)
    if type(jwks) ~= "string" then
      if issuer_entity then
        log.notice("encoding jwks keys failed: ", err or "unknown error",
                   " (falling back to previous keys)")
        jwks = issuer_entity.keys

      else
        log.err("encoding jwks keys failed: ", err or "unknown error",
                   " (falling back to empty keys)")
        jwks = "[]"
      end
    end

  else
    if issuer_entity then
      log.notice("no keys found (falling back to previous keys)")
      jwks = issuer_entity.keys

    else
      log.warn("no keys found (falling back to empty keys)")
      jwks = "[]"
    end
  end

  local updated_at = time()
  configuration_decoded.updated_at = updated_at

  local encoded
  encoded, err = json.encode(configuration_decoded)
  if type(encoded) ~= "string" then
    if issuer_entity then
      log.notice("encoding discovery document failed: ", err or "unknown error",
                 " (falling back to previous configuration)")
                 encoded = issuer_entity.configuration

    else
      log.err("encoding discovery document failed: ", err or "unknown error",
                 " (falling back to empty configuration)")

      encoded = json.encode({
        issuer = issuer,
        updated_at = updated_at,
      })
    end
  end

  return encoded, jwks
end


local function issuer_select(identifier)
  if kong.configuration.database == "off" and discovery_data[identifier] then
    return discovery_data[identifier]
  end

  log.notice("loading configuration for ", identifier, " from database")

  local issuer_entity, err = kong.db.oic_issuers:select_by_issuer(identifier)
  if err then
    log.err("unable to load discovery data (", err, ")")
  end

  -- `kong.db.oic_issuers:select_by_issuer` may yield, and thus lets just
  -- check again that no other light thread has already filled the discovery
  -- cache.
  if kong.configuration.database == "off" and discovery_data[identifier] then
    return discovery_data[identifier]
  end

  if kong.configuration.database == "off" and type(issuer_entity) == "table" then
    discovery_data.n = discovery_data.n + 1
    discovery_data[discovery_data.n] = issuer_entity
    discovery_data[issuer_entity.id] = issuer_entity
    discovery_data[issuer_entity.issuer] = issuer_entity
  end

  return issuer_entity
end


local function issuer_identifier(issuer, opts)
  local extra_jwks_uris = opts and opts.extra_jwks_uris
  if extra_jwks_uris and #extra_jwks_uris > 0 then
    sort(extra_jwks_uris)
    local hash = sha256_base64url(concat(extra_jwks_uris, ":"))
    return issuer .. "#" .. hash
  end
  return issuer
end


local function rediscover(issuer, identifier, opts, issuer_entity)
  if not issuer_entity then
    issuer_entity = issuer_select(identifier)
  end

  local conf, jwks = discover(issuer, opts, issuer_entity)
  if not conf or not jwks then
    log.notice("rediscovery failed")
    issuer_entity = issuer_select(identifier)
  end

  if issuer_entity then
    local data = {
      issuer        = identifier,
      configuration = conf or issuer_entity.configuration,
      keys          = jwks or issuer_entity.keys,
      secret        = issuer_entity.secret,
    }

    if kong.configuration.database == "off" then
      data.id = issuer_entity.id
      data.created_at = issuer_entity.created_at

      if discovery_data[data.issuer] then
        for i = 1, discovery_data.n do
          if discovery_data[i].id == data.id then
            discovery_data[i] = data
            break
          end
        end

      else
        discovery_data.n = discovery_data.n + 1
        discovery_data[discovery_data.n] = data
      end

      discovery_data[data.id] = data
      discovery_data[data.issuer] = data

      local key = cache_key(data.issuer, "oic_issuers")
      cache_invalidate(key)
      cache_get(key, nil, function()
        return data
      end)

    else
      local stored_data, err = kong.db.oic_issuers:upsert({ id = issuer_entity.id }, data)
      if not stored_data then
        log.warn("unable to upsert issuer ", data.issuer, " discovery documents in database (",
                err or "unknown error", ")")
      else
        data = stored_data
      end
    end

    return data.keys

  else
    local created_at = time()

    conf = conf or json.encode({
      issuer = issuer,
      updated_at = created_at,
    })

    local data = {
      issuer        = identifier,
      configuration = conf,
      keys          = jwks or "[]",
      secret        = get_secret(),
    }

    if kong.configuration.database == "off" then
      data.id = utils.uuid()
      data.created_at = created_at
      discovery_data.n = discovery_data.n + 1
      discovery_data[discovery_data.n] = data
      discovery_data[data.id] = data
      discovery_data[data.issuer] = data

      local key = cache_key(data.issuer, "oic_issuers")
      cache_invalidate(key)
      cache_get(key, nil, function()
        return data
      end)

    else
      local stored_data, err = kong.db.oic_issuers:upsert_by_issuer(data.issuer, data)
      if not stored_data then
        log.warn("unable to upsert issuer ", data.issuer, " discovery documents in database (",
                err or "unknown error", ")")

        issuer_entity = issuer_select(data.issuer)
        if issuer_entity then
          return issuer_entity.keys
        end

      else
        data = stored_data
      end
    end

    return data.keys
  end
end


local issuers = {}


function issuers.rediscover(issuer, opts)
  issuer = normalize_issuer(issuer)
  opts = opts or {}

  local identifier = issuer_identifier(issuer, opts)
  local issuer_entity = issuer_select(identifier)
  local updated_at = 0

  if issuer_entity then
    local configuration_decoded, err = json.decode(issuer_entity.configuration)
    if type(configuration_decoded) == "table" then
      updated_at = configuration_decoded.updated_at or 0

    else
      log.notice("rediscovery failed when decoding discovery for ",
                 identifier, " (", err, ")")
    end

    local rediscovery_lifetime = opts.rediscovery_lifetime or 30
    local seconds_since_last_rediscovery = time() - updated_at
    if seconds_since_last_rediscovery < rediscovery_lifetime then
      log.notice("rediscovery for ", identifier, " was done recently (",
                 rediscovery_lifetime - seconds_since_last_rediscovery,
                 " seconds until next rediscovery)")
      return issuer_entity.keys
    end
  end

  local err
  local rediscovery_semaphore = rediscovery_semaphores[identifier]
  if not rediscovery_semaphore then
    rediscovery_semaphore, err = semaphore.new(1)
    if err then
      log.warn("rediscovery was unable to create a semaphore for ",
              identifier, " (", err, ")")
    else
      rediscovery_semaphores[identifier] = rediscovery_semaphore
    end
  end

  local locked
  local new_issuer_entity
  if rediscovery_semaphore then
    -- waiting at most 1.5 seconds, last wait being half a second
    for i = 1, 5 do
      locked, err = rediscovery_semaphore:wait(0.1 * i)
      new_issuer_entity = issuer_select(identifier)
      if new_issuer_entity then
        local configuration_decoded = json.decode(new_issuer_entity.configuration)
        local new_updated_at = type(configuration_decoded) == "table" and
                               configuration_decoded.updated_at or 0

        if new_updated_at > updated_at then
          if locked then
            rediscovery_semaphore:post()
          end
          return new_issuer_entity.keys
        end
      end

      if locked then
        break
      end
    end
  end

  if not locked then
    -- Couldn't get a lock and the keys were not updated during 1.5 seconds.
    -- We return old keys, and this will most likely result 401 on the client.
    log.notice("unable to acquire a lock for ", identifier, " rediscovery (", err, ")")
    if new_issuer_entity then
      return new_issuer_entity.keys or "[]"
    end

    if issuer_entity then
      return issuer_entity.keys or "[]"
    end

    return "[]"
  end

  local new_keys = rediscover(issuer, identifier, opts, new_issuer_entity)
  if locked then
    rediscovery_semaphore:post()
  end

  return new_keys
end


local function issuers_init(issuer, identifier, opts)
  local issuer_entity = issuer_select(identifier)
  if issuer_entity then
    return issuer_entity
  end

  local conf, jwks = discover(issuer, opts, issuer_entity)
  if not conf then
    return nil, "discovery failed"
  end

  issuer_entity = issuer_select(identifier)
  if issuer_entity then
    return issuer_entity
  end

  local created_at = time()

  conf = conf or json.encode({
    issuer = issuer,
    updated_at = created_at,
  })

  local data = {
    issuer        = identifier,
    configuration = conf,
    keys          = jwks or "[]",
    secret        = get_secret(),
  }

  if kong.configuration.database == "off" then
    data.id = utils.uuid()
    data.created_at = created_at
    discovery_data.n = discovery_data.n + 1
    discovery_data[discovery_data.n] = data
    discovery_data[data.id] = data
    discovery_data[data.issuer] = data

  else
    local stored_data, err = kong.db.oic_issuers:upsert_by_issuer(data.issuer, data)
    if not stored_data then
      log.err("unable to upsert ", data.issuer, " discovery documents in database (", err, ")")

      issuer_entity = issuer_select(data.issuer)
      if issuer_entity then
        return issuer_entity
      end

      if not data.id then
        data.id = utils.uuid()
      end

      if not data.created_at then
        data.created_at = created_at
      end

    else
      data = stored_data
    end
  end

  return data
end


function issuers.load(issuer, opts)
  issuer = normalize_issuer(issuer)
  local identifier = issuer_identifier(issuer, opts)
  local key = cache_key(identifier, "oic_issuers")
  return cache_get(key, nil, issuers_init, issuer, identifier, opts)
end


local function log_multiple_matches(subject, matches)
  local match_info = {}
  for _, match in pairs(matches) do
    insert(match_info, fmt("%s (id: %s)", match.username, match.id))
  end
  log.notice(fmt("multiple consumers match '%s' by username case-insensitively: %s",
                 subject, concat(match_info, ", ")))
end


local consumers = {}


local function consumers_load(subject, key, by_username_ignore_case)
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
    if not result and by_username_ignore_case then
      result, err = kong.db.consumers:select_by_username_ignore_case(subject)
      if #result > 1 then
        log_multiple_matches(subject, result)
      end

      result = result[1]
    end
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


function consumers.load(subject, anonymous, consumer_by, ttl, by_username_ignore_case)
  local field_names
  -- when `anonymous` is set, expect format to be either "id" or "username"
  if anonymous then
    field_names = { "id", "username" }

  -- allow overwrites with `consumer_by`
  elseif consumer_by then
    field_names = consumer_by

  -- by default, search for all known fields -> custom_id, username and uuid
  else
    field_names = { "custom_id", "username", "id" }
  end

  local err
  for _, field_name in ipairs(field_names) do
    local key

    if field_name == "id" then
      key = kong.db.consumers:cache_key(subject)

    elseif field_name == "username" and by_username_ignore_case then
      key = kong.db.consumers:cache_key(field_name .. "_lower", subject)

    else
      key = kong.db.consumers:cache_key(field_name, subject)
    end

    local consumer
    consumer, err = cache_get(key, ttl, consumers_load, subject, field_name, by_username_ignore_case)
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

  local credential_cache_key = cache_key(token.credential.id, "oauth2_credentials")
  local credential
  credential, err = cache_get(credential_cache_key, ttl_new, kong_oauth2_credential, token.credential)
  if not credential then
    return nil, err
  end

  local consumer_cache_key = cache_key(credential.consumer.id, "consumers")
  local consumer
  consumer, err = cache_get(consumer_cache_key, ttl_new, kong_oauth2_consumer, credential.consumer)
  if not consumer then
    return nil, err
  end

  return token, nil, credential, consumer
end


local introspection = {}


local function introspection_load(oic, access_token, hint, ttl, ignore_signature, opts)
  log.notice("introspecting access token with identity provider")
  local body, err, headers = oic.token:introspect(access_token, hint or "access_token", opts)
  if not body then
    return nil, err or "unable to introspect token"
  end

  local token
  local jwt

  token, err, jwt = parse_jwt_response(oic, body, headers, ignore_signature, "application/token-introspection+jwt")
  if not token then
    if err then
      return nil, "unable to parse introspection response: " .. err
    else
      return nil, "unable to parse introspection response"
    end
  end

  local exp, cache_ttl = get_expiry_and_cache_ttl(token, ttl)

  return { exp, token, jwt }, nil, cache_ttl
end


function introspection.load(oic, access_token, hint, ttl, use_cache, ignore_signature, opts)
  if not access_token then
    return nil, "no access token given for token introspection"
  end

  local key = cache_key(sha256_base64url(concat({
    opts.introspection_endpoint or oic.configuration.issuer,
    access_token
  }, "#introspection=")))

  local res
  local err

  if use_cache and key then
    res, err = cache_get("oic:" .. key, ttl, introspection_load, oic, access_token, hint, ttl, ignore_signature, opts)
    if type(res) ~= "table" then
      return nil, err or "unable to introspect token"
    end

    local exp = res[1]
    if exp ~= 0 and exp < ttl.now then
      cache_invalidate("oic:" .. key)
      res, err = introspection_load(oic, access_token, hint, ttl, ignore_signature, opts)
    end

  else
    res, err = introspection_load(oic, access_token, hint, ttl, ignore_signature, opts)
  end

  if type(res) ~= "table" then
    return nil, err or "unable to introspect token"
  end

  local token = res[2]
  local jwt   = res[3]
  return token, nil, jwt
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


local function get_token_cache_key(iss, salt, args)
  if not args.grant_type then return nil end

  local buffer = string_buffer.new()
  buffer:put(iss, "#grant_type=", args.grant_type)

  if args.grant_type == "refresh_token" then
    assert(args.refresh_token, "no credentials given for refresh token grant")

    buffer:put("&", args.refresh_token)
  elseif args.grant_type == "password" then
    assert(args.username and args.password, "no credentials given for password grant")

    buffer:put("&", args.username, "&", args.password)
  elseif args.grant_type == "client_credentials" then
    assert((args.client_id and args.client_secret) or args.assertion,
      "no credentials given for client credentials grant")

    if args.assertion then
      buffer:put("&", args.assertion)
    else
      buffer:put("&", args.client_id, "&", args.client_secret)
    end
  else
    return nil
  end

  if salt then
    buffer:put("&", salt)
  end

  local scope = args.args and args.args.scope
  if args.token_cache_key_include_scope and scope
    and args.grant_type ~= "refresh_token" then
      buffer:put("&", url_encode(scope))
  end

  return cache_key(sha256_base64url(buffer:get()))
end


function tokens.load(oic, args, ttl, use_cache, flush, salt)
  local res
  local err
  local key

  if use_cache or flush then
    local ok
    ok, key = pcall(get_token_cache_key, oic.configuration.issuer, salt, args)
    if not ok then return nil, key end

    if key then key = "oic:" .. key end

    if flush and key then
      cache_invalidate(key)
    end
  end

  if use_cache and key then
    res, err = cache_get(key, ttl, tokens_load, oic, args, ttl)
    if type(res) ~= "table" then
      return nil, err or "unable to exchange credentials"
    end

    local exp = res[1]
    if exp ~= 0 and exp < ttl.now then
      cache_invalidate(key)
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
      return nil, err
    end
  end

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

  local key = cache_key(sha256_base64url(concat({
    endpoint,
    access_token
  }, "#exchange=")))

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


local function userinfo_load(oic, access_token, ttl, ignore_signature, opts)
  log.notice("loading user info using access token from identity provider")

  local body, err, headers = oic:userinfo(access_token, opts)
  if not body then
    return nil, err
  end

  local token
  local jwt

  token, err, jwt = parse_jwt_response(oic, body, headers, ignore_signature, "application/userinfo+jwt")
  if not token then
    if err then
      return nil, "unable to parse userinfo response: " .. err
    else
      return nil, "unable to parse userinfo response"
    end
  end

  local exp, cache_ttl = get_expiry_and_cache_ttl(token, ttl)

  return { exp, token, jwt }, nil, cache_ttl
end


function userinfo.load(oic, access_token, ttl, use_cache, ignore_signature, opts)
  if not access_token then
    return nil, "no access token given for user info"
  end

  local key = cache_key(sha256_base64url(concat({
    oic.configuration.issuer,
    access_token
  }, "#userinfo=")))

  local res, err
  if use_cache and key then
    res, err = cache_get("oic:" .. key, ttl, userinfo_load, oic, access_token, ttl, ignore_signature, opts)
    if type(res) ~= "table" then
      return nil, err or "unable to load user info"
    end

    local exp = res[1]
    if exp ~= 0 and exp < ttl.now then
      cache_invalidate("oic:" .. key)
      res, err = userinfo_load(oic, access_token, ttl, ignore_signature, opts)
    end
  else
    res, err = userinfo_load(oic, access_token, ttl, ignore_signature, opts)
  end

  if type(res) ~= "table" then
    return nil, err or "unable to load user info"
  end

  local token = res[2]
  local jwt   = res[3]

  return token, nil, jwt
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
  discovery_data = discovery_data,
}
