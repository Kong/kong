require "kong.plugins.jwt-signer.env"


local utils       = require "kong.tools.utils"
local codec       = require "kong.openid-connect.codec"
local token       = require "kong.openid-connect.token"
local jwks        = require "kong.openid-connect.jwks"
local keys        = require "kong.openid-connect.keys"
local hash        = require "kong.openid-connect.hash"
local log         = require "kong.plugins.jwt-signer.log"


local tablex      = require "pl.tablex"
local json        = require "cjson.safe"


local decode_args = ngx.decode_args
local encode_args = ngx.encode_args
local tonumber    = tonumber
local concat      = table.concat
local base64      = codec.base64
local ipairs      = ipairs
local time        = ngx.time
local find        = string.find
local type        = type
local null        = ngx.null
local kong        = kong


local function init_worker()
  if not kong.worker_events or not kong.worker_events.register then
    return
  end

  kong.worker_events.register(function(data)
    log("consumer updated, invalidating cache")

    local old_entity = data.old_entity
    if old_entity then
      if old_entity.custom_id and old_entity.custom_id ~= null and old_entity.custom_id ~= "" then
        kong.cache:invalidate(kong.db.consumers:cache_key("custom_id", old_entity.custom_id))
      end

      if old_entity.username and old_entity.username ~= null and old_entity.username ~= "" then
        kong.cache:invalidate(kong.db.consumers:cache_key("username", old_entity.username))
      end
    end

    local entity = data.entity
    if entity then
      if entity.custom_id and entity.custom_id ~= null and entity.custom_id ~= "" then
        kong.cache:invalidate(kong.db.consumers:cache_key("custom_id", entity.custom_id))
      end

      if entity.username and entity.username ~= null and entity.username ~= "" then
        kong.cache:invalidate(kong.db.consumers:cache_key("username", entity.username))
      end
    end
  end, "crud", "consumers")
end


local rediscover_keys


local function load_keys_db(name)
  log("loading jwks from database for ", name)

  local row, err

  if utils.is_valid_uuid(name) then
    row, err = kong.db.jwt_signer_jwks:select { id = name }
  else
    row, err = kong.db.jwt_signer_jwks:select_by_name(name)
  end

  return row, err
end


local function rotate_keys(name, row, update, force)
  local err
  local now = time()

  if find(name, "https://", 1, true) == 1 or find(name, "http://", 1, true) == 1 then
    if not row then
      log("loading jwks from ", name)

      row, err = keys.load(name, { ssl_verify = false, unwrap = true, json = true })
      if not row then
        return nil, err
      end

      row, err = kong.db.jwt_signer_jwks:insert({
        name       = name,
        keys       = row,
      })

      if not row then
        return nil, err
      end

    elseif update ~= false then
      local updated_at = row.updated_at or 0

      if not force and now - updated_at < 300 then
        log.notice("jwks were rotated less than 5 minutes ago (skipping)")

      else
        log("rotating jwks for ", name)

        local previous_keys, current_keys

        previous_keys = row.keys
        if type(previous_keys) == "table" then
          previous_keys, err = json.encode(previous_keys)
          if not previous_keys then
            return nil, err
          end
        end

        current_keys, err = keys.load(name, { ssl_verify = false, unwrap = true, json = true })
        if not current_keys then
          return nil, err
        end

        local data = { keys = current_keys, previous = previous_keys, updated_at = now }
        local id = { id = row.id }

        row, err = kong.db.jwt_signer_jwks:update(id, data)

        if not row then
          return nil, err
        end
      end
    end

    local options = {
      rediscover_keys = rediscover_keys(name, row)
    }

    return keys.new({ jwks_uri = name, options = options }, row.keys, row.previous)

  else
    if not row then
      log("creating jwks for ", name)

      row, err = jwks.new({ json = true, unwrap = true })
      if not row then
        return nil, err
      end

      row, err = kong.db.jwt_signer_jwks:insert({
        name       = name,
        keys       = row,
      })

      if not row then
        return nil, err
      end

    elseif update ~= false then
      log("rotating jwks for ", name)

      local previous_keys, current_keys

      previous_keys = row.keys
      if type(previous_keys) == "table" then
        previous_keys, err = json.encode(previous_keys)
        if not previous_keys then
          return nil, err
        end
      end

      current_keys, err = jwks.new({ json = true, unwrap = true })
      if not current_keys then
        return nil, err
      end

      local data = { keys = current_keys, previous = previous_keys, updated_at = now }
      local id = { id = row.id }

      row, err = kong.db.jwt_signer_jwks:update(id, data)
      if not row then
        return nil, err
      end
    end

    return keys.new({}, row.keys, row.previous)
  end
end


rediscover_keys = function(name, row)
  return function()
    log("rediscovering keys for ", name)
    return rotate_keys(name, row)
  end
end


local function load_keys(name)
  local cache_key = kong.db.jwt_signer_jwks:cache_key(name)
  local row, err = kong.cache:get(cache_key, nil, load_keys_db, name)
  if err then
    log(err)
  end

  return rotate_keys(name, row, false)
end


local function load_consumer_db(subject, by)
  if not subject or subject == "" then
    return nil, "unable to load consumer by a missing subject"
  end

  local result, err
  log.notice("loading consumer by  ", by, " using ", subject)

  if by == "id" then
    if not utils.is_valid_uuid(subject) then
      return nil, "invalid id " .. subject
    end
    result, err = kong.db.consumers:select { id = subject }
  elseif by == "username" then
    result, err = kong.db.consumers:select_by_username(subject)
  elseif by == "custom_id" then
    result, err = kong.db.consumers.select_by_custom_id(subject)
  else
    return nil, "consumer cannot be loaded by " .. by
  end

  if type(result) == "table" then
      return result
  end

  if err then
    log.notice("failed to load consumer (", err, ")")

  else
    log.notice("failed to load consumer")
  end

  return nil, err
end


local function load_consumer(subject, consumer_by)
  consumer_by = consumer_by or {
    "username",
    "custom_id",
  }

  local err
  for _, by in ipairs(consumer_by) do
    local cache_key
    if by == "id" then
      cache_key = kong.db.consumers:cache_key(subject)
    else
      cache_key = kong.db.consumers:cache_key(by, subject)
    end

    local consumer
    consumer, err = kong.cache:get(cache_key, nil, load_consumer_db, subject, by)
    if consumer then
      return consumer
    end
  end

  return nil, err
end


local function introspect_uri(endpoint, opaque_token, hint, authorization, args, timeout)
  local options = {
    token_introspection_endpoint = endpoint,
    ssl_verify                   = false,
    timeout                      = timeout,
  }

  if authorization then
    options.headers = {
      Authorization = authorization
    }
  end

  if args then
    if type(args) == "string" then
      args = decode_args(args)
    end

    if type(args) == "table" then
      options.args = args
    end
  end

  return token:introspect(opaque_token, hint, options)
end


local function introspect_uri_cache(endpoint, opaque_token, hint, authorization, args, now, timeout)
  log("introspecting token with ", endpoint)

  local token_info, err = introspect_uri(endpoint, opaque_token, hint, authorization, args, timeout)
  if not token_info then
    return nil, err or "unable to introspect token"
  end

  local exp
  local expires_in
  if type(token_info) == "table" then
    exp = tonumber(token_info.exp)
    expires_in = tonumber(token_info.expires_in)
  end

  if not expires_in and exp then
    expires_in = exp - now
  end

  if not exp and expires_in then
    exp = now + expires_in
  end

  return { token_info, exp }, nil, expires_in
end


local function introspect(endpoint, opaque_token, hint, authorization, args, cache, timeout)
  if not endpoint then
    return nil, "no endpoint given for introspection"
  end

  if not opaque_token then
    return nil, "no token given for introspection"
  end

  if cache then
    local cache_key = {
        endpoint,
        opaque_token,
    }

    local i = 2

    if hint then
      i = i + 1
      cache_key[i] = hint
    end

    if authorization then
      i = i + 1
      cache_key[i] = authorization
    end

    local args_table
    if args then
      if type(args) == "table" then
        args_table = args
        args = encode_args(args)
      end

      i = i + 1
      cache_key[i] = args
    end

    cache_key = base64.encode(hash.S256(concat(cache_key)))
    if cache_key then
      cache_key = "jwt-signer:" .. cache_key

      local now = time()
      local res, err = kong.cache:get(cache_key,
                                      nil,
                                      introspect_uri_cache,
                                      endpoint,
                                      opaque_token,
                                      hint,
                                      authorization,
                                      args_table or args,
                                      now,
                                      timeout)

      if not res then
        return nil, err or "unable to introspect token"
      end

      local exp = res[2]
      if exp and now > exp then
        kong.cache:invalidate(cache_key)
        return introspect_uri(endpoint, opaque_token, hint, authorization, args_table or args, timeout)
      end

      return tablex.deepcopy(res[1])

    else
      log("unable to generate a cache key for introspection")
    end
  end

  return introspect_uri(endpoint, opaque_token, hint, authorization, args, timeout)
end


return {
  init_worker   = init_worker,
  load_keys     = load_keys,
  load_consumer = load_consumer,
  rotate_keys   = rotate_keys,
  introspect    = introspect,
}
