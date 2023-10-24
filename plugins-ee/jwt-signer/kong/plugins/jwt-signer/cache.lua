-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

require "kong.plugins.jwt-signer.env"


local utils       = require "kong.tools.utils"
local codec       = require "kong.openid-connect.codec"
local token       = require "kong.openid-connect.token"
local jwks        = require "kong.openid-connect.jwks"
local keys        = require "kong.openid-connect.keys"
local hash        = require "kong.openid-connect.hash"
local log         = require "kong.plugins.jwt-signer.log"
local workspaces  = require "kong.workspaces"


local worker_id   = ngx.worker.id
local decode_args = ngx.decode_args
local encode_args = ngx.encode_args
local timer_at    = ngx.timer.at
local tonumber    = tonumber
local concat      = table.concat
local base64      = codec.base64
local ipairs      = ipairs
local time        = ngx.time
local find        = string.find
local type        = type
local null        = ngx.null
local kong        = kong


local KEYS = {}


local function cache_jwks(data)
  return data
end


local function warmup(premature)
  if premature then
    return
  end

  if kong and kong.db and kong.db.jwt_signer_jwks then
    for row, err in kong.db.jwt_signer_jwks:each() do
      if err then
        log.warn("warmup of jwks cache failed with: ", err)
        break
      end

      if row.name then
        local cache_key = kong.db.jwt_signer_jwks:cache_key(row.name)
        kong.cache:get(cache_key, nil, cache_jwks, row)
      end
    end
  end
end


local function init_worker()
  KEYS = {}

  if worker_id() == 0 then
    local ok, err = timer_at(0, warmup)
    if not ok then
      log.warn("unable to create jwks cache warmup timer: ", err)
    end
  end

  if kong.configuration.database == "off" or not (kong.worker_events and kong.worker_events.register) then
    return
  end

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

  if kong.configuration.database == "off" then
    if not row then
      row = KEYS[name]
      if row then
        return row
      end

    else
      KEYS[name] = row
    end
  end

  return row, err
end


local function rotate_keys(name, row, update, force, ret_err)
  local now = time()

  if find(name, "https://", 1, true) == 1 or find(name, "http://", 1, true) == 1 then
    if not row then
      log("loading jwks from ", name)

      local current_keys, err = keys.load(name, { ssl_verify = false, unwrap = true, json = false })
      if not current_keys then
        if ret_err then
          return nil, err
        end

        if kong.configuration.database == "off" and KEYS[name] then
          log.notice("loading jwks from ", name, " failed: ", err or "unknown error",
                     " (falling back to cached jwks)")
          row = KEYS[name]

        else
          log.notice("loading jwks from ", name, " failed: ", err or "unknown error",
                     " (falling back to empty jwks)")
          current_keys = {}
        end
      end

      if kong.configuration.database == "off" then
        if not row then
          row = {
            id = utils.uuid(),
            name = name,
            keys = current_keys,
            created_at = now,
            updated_at = now
          }
        end

      else
        local stored_data
        if not err then
          stored_data, err = kong.db.jwt_signer_jwks:upsert_by_name(name, {
            keys = current_keys,
          })
        end
        if stored_data then
          row = stored_data

        else
          if ret_err then
            return nil, err
          end

          log.warn("unable to upsert ", name, " jwks to database (", err
                   or "unknown error", ")")

          stored_data, err = kong.db.jwt_signer_jwks:select_by_name(name)
          if stored_data then
            row = stored_data

          else
            if err then
              if ret_err then
                return nil, err
              end

              log.warn("failed to load ", name, " jwks from database (", err, ")")
            end

            if not row then
              row = {
                id = utils.uuid(),
                name = name,
                keys = current_keys,
                created_at = now,
                updated_at = now
              }
            end
          end
        end
      end

    elseif update ~= false then
      local updated_at = row.updated_at or 0

      if not force and now - updated_at < 300 then
        if ret_err then
          return nil, "jwks were rotated less than 5 minutes ago (skipping)"
        end

        log.notice("jwks were rotated less than 5 minutes ago (skipping)")

      else
        log("rotating jwks for ", name)

        local previous_keys = row.keys
        local current_keys, err = keys.load(name, { ssl_verify = false, unwrap = true, json = false })
        if current_keys then
          local id = {
            id = row.id
          }

          row = {
            name = name,
            keys = current_keys,
            previous = previous_keys,
            created_at = row.created_at or now,
            updated_at = now,
          }

          if kong.configuration.database == "off" then
            row.id = id.id or utils.uuid()
            KEYS[name] = row
            local cache_key = kong.db.jwt_signer_jwks:cache_key(name)
            kong.cache:invalidate_local(cache_key)
            kong.cache:get(cache_key, nil, cache_jwks, row)

          else
            local stored_data
            stored_data, err = kong.db.jwt_signer_jwks:upsert(id, row)
            if stored_data then
              row = stored_data

            else
              if ret_err then
                return nil, err
              end

              log.warn("unable to upsert ", name, " jwks to database (", err
                       or "unknown error", ")")

              row.id = id.id
            end
          end

        else
          if ret_err then
            return nil, err
          end

          log.warn("failed to load ", name, " jwks from database (", err, ")")
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

      local current_keys, err = jwks.new({ unwrap = true, json = false })
      if not current_keys then
        if ret_err then
          return nil, err
        end

        if kong.configuration.database == "off" and KEYS[name] then
          log.notice("creating jwks for ", name, " failed: ", err or "unknown error",
                     " (falling back to cached jwks)")
          row = KEYS[name]

        else
          log.warn("creating jwks for ", name, " failed: ", err or "unknown error",
                   " (falling back to empty configuration)")

          current_keys = {}
        end
      end

      if kong.configuration.database == "off" then
        if not row then
          row = {
            id   = utils.uuid(),
            name = name,
            keys = current_keys,
            created_at = now,
            updated_at = now,
          }
        end

      else
        local stored_data
        if not err then
          stored_data, err = kong.db.jwt_signer_jwks:upsert_by_name(name, {
            keys = current_keys,
          })
        end
        if stored_data then
          row = stored_data

        else
          if ret_err then
            return nil, err
          end

          log.warn("unable to upsert ", name, " jwks to database (", err
                   or "unknown error", ")")

          stored_data, err = kong.db.jwt_signer_jwks:select_by_name(name)
          if stored_data then
            row = stored_data

          else
            if err then
              if ret_err then
                return nil, err
              end

              log.warn("failed to load issuer ", name, " jwks from database (", err, ")")
            end

            if not row then
              row = {
                id = utils.uuid(),
                name = name,
                keys = current_keys,
                created_at = now,
                updated_at = now
              }
            end
          end
        end
      end

    elseif update ~= false then
      log("rotating jwks for ", name)

      local previous_keys = row.keys
      local current_keys, err = jwks.new({ unwrap = true, json = false })
      if current_keys then
        local id = {
          id = row.id
        }

        row = {
          name = name,
          keys = current_keys,
          previous = previous_keys,
          created_at = row.created_at or now,
          updated_at = now,
        }

        if kong.configuration.database == "off" then
          row.id = id.id or utils.uuid()
          KEYS[name] = row

        else
          local stored_data
          stored_data, err = kong.db.jwt_signer_jwks:upsert(id, row)
          if stored_data then
            row = stored_data

          else
            if ret_err then
              return nil, err
            end

            log.warn("unable to upsert ", name, " jwks to database (", err
                     or "unknown error", ")")

            row.id = id.id
          end
        end

      else
        if ret_err then
          return nil, err
        end

        log.warn("failed to create keys for ", name, " (", err, ")")
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
  log.notice("loading consumer by ", by, " using ", subject)

  if by == "id" then
    if not utils.is_valid_uuid(subject) then
      return nil, "invalid id " .. subject
    end
    result, err = kong.db.consumers:select { id = subject }
  elseif by == "username" then
    result, err = kong.db.consumers:select_by_username(subject)
  elseif by == "custom_id" then
    result, err = kong.db.consumers:select_by_custom_id(subject)
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
        kong.cache:invalidate_local(cache_key)
        return introspect_uri(endpoint, opaque_token, hint, authorization, args_table or args, timeout)
      end

      return utils.cycle_aware_deep_copy(res[1])

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
  keys          = keys,
}
