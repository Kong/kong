-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local utils       = require "kong.tools.utils"
local codec       = require "kong.openid-connect.codec"
local token       = require "kong.openid-connect.token"
local jwks        = require "kong.openid-connect.jwks"
local keys        = require "kong.openid-connect.keys"
local hash        = require "kong.openid-connect.hash"
local log         = require "kong.plugins.jwt-signer.log"
local workspaces  = require "kong.workspaces"
local certificate = require "kong.runloop.certificate"
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy


local worker_id   = ngx.worker.id
local decode_args = ngx.decode_args
local encode_args = ngx.encode_args
local timer_at    = ngx.timer.at
local tonumber    = tonumber
local concat      = table.concat
local base64      = codec.base64
local credentials = codec.credentials
local ipairs      = ipairs
local time        = ngx.time
local find        = string.find
local type        = type
local null        = ngx.null
local kong        = kong
local get_cert    = certificate.get_certificate
local fmt         = string.format

local JWKS_CACHE_KEY = "JWT_SIGNER_JWKS:GLOBAL"

local function cache_jwks(data)
  return data
end

local strategy

local strategies = {
  ["postgres"] = {
    store_keys = function(name, row)
      row.id = nil
      return kong.db.jwt_signer_jwks:upsert_by_name(name, row)
    end,
    select = function(name)
      log("loading jwks from database for ", name)

      local row, err

      if utils.is_valid_uuid(name) then
        row, err = kong.db.jwt_signer_jwks:select { id = name }
      else
        row, err = kong.db.jwt_signer_jwks:select_by_name(name)
      end

      return row, err
    end,
    select_all_keys = function()
      local rows = {}
      for row in kong.db.jwt_signer_jwks:each() do
        table.insert(rows, row)
      end

      return rows
    end
  },
  ["off"] = {
    store_keys = function(name, row)
      if not row then
        return nil
      end

      local jwks_cache, err = kong.cache:get(JWKS_CACHE_KEY, nil, cache_jwks, {})
      if err then
        return nil, err
      end
      kong.cache:invalidate(JWKS_CACHE_KEY)
      row.name = name
      jwks_cache[name] = row
      kong.cache:get(JWKS_CACHE_KEY, nil, cache_jwks, jwks_cache)

      return row
    end,
    select = function(name)
      local jwks_cache = kong.cache:get(JWKS_CACHE_KEY)
      local row = jwks_cache and jwks_cache[name]
      return row
    end,
    select_all_keys = function()
      return kong.cache:get(JWKS_CACHE_KEY, nil, cache_jwks, {})
    end
  }
}

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
  kong.cache:invalidate(JWKS_CACHE_KEY)
  strategy = strategies[kong.configuration.database]

  if worker_id() == 0 then
    local ok, err = timer_at(0, warmup)
    if not ok then
      log.warn("unable to create jwks cache warmup timer: ", err)
    end
  end

  if not (kong.worker_events and kong.worker_events.register) then
    return
  end

  -- dbless without rpc will not register events (incremental sync)
  if kong.configuration.database == "off" and not kong.sync then
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

local function create_keys_object(row, name, current_keys)
  local now = time()

  return {
    id = row and row.id or utils.uuid(),
    name = name,
    keys = current_keys,
    previous = row and row.keys,
    created_at = row and row.created_at or now,
    updated_at = now,
  }
end


local function is_rotated_recently(row, period)
  if row and row.updated_at then
    local now = time()
    local time_since_last_update = now - row.updated_at
    if time_since_last_update < period then
      return time_since_last_update
    end
  end
end


local function rotate_keys(name, row, update, force, ret_err, opts)
  local is_http = find(name, "http://", 1, true) == 1
  local is_https = find(name, "https://", 1, true) == 1
  local is_uri = is_http or is_https
  local need_load
  local action
  local current_keys, err, err_str

  if is_uri then
    action = "loading jwks from "
  else
    action = "creating jwks for "
  end

  if not row then
    log(action, name)
    need_load = true

  elseif update ~= false then
    if is_uri and not force and is_rotated_recently(row, 300) then
      if ret_err then
        return nil, "jwks were rotated less than 5 minutes ago (skipping)"
      end

      log.notice("jwks were rotated less than 5 minutes ago (skipping)")

    else
      action = "rotating jwks for "

      log(action, name)
      need_load = true
    end
  end

  if need_load then
    if is_uri then
      local headers, client_cert, client_key
      if opts and opts.client_username and opts.client_password then
        local cred
        cred, err = credentials.encode(opts.client_username, opts.client_password)
        if cred then
          headers = {
            Authorization = "Basic " .. cred
          }
        else
          err_str = fmt("failed to encode credentials: %s", err or "unknown error")

          if ret_err then
            return nil, err_str
          end

          log.warn(err_str)
        end
      end

      if is_https and opts and opts.client_certificate then
        local cert
        cert, err = get_cert(opts.client_certificate)
        if cert then
          client_cert = cert.cert
          client_key = cert.key

        else
          err_str = fmt("failed to get client certificate: %s", err or "unknown error")

          if ret_err then
            return nil, err_str
          end

          log.warn(err_str)
        end
      end

      current_keys, err = keys.load(name, { ssl_verify = false, unwrap = true, json = false, headers = headers,
                                            ssl_client_cert = client_cert, ssl_client_priv_key = client_key })
    else
      current_keys, err = jwks.new({ unwrap = true, json = false })
    end

    if current_keys then
      local keys_object = create_keys_object(row, name, current_keys)
      row, err = strategy.store_keys(name, keys_object)
      if err then
        err_str = fmt("unable to upsert %s jwks to database or cache (%s)", name, err or "unknown error")

        if ret_err then
          return nil, err_str
        end

        log.warn(err_str)
      end
    else
      err_str = fmt("%s%s failed: %s", action, name, err or "unknown error")

      if ret_err then
        return nil, err_str
      end

      log.warn(err_str)

      if not row then
        row, err = strategy.select(name)
        if err then
          err_str = fmt("failed to load %s jwks from database or cache (%s)", name, err)

          if ret_err then
            return nil, err_str
          end
          log.warn(err_str)
        end

        if not row then
          log.warn("falling back to empty jwks")
          row = create_keys_object(nil, name, {})
        end
      end
    end
  end

  if is_uri then
    local options = {
      rediscover_keys = rediscover_keys(name, row, opts)
    }

    return keys.new({ jwks_uri = name, options = options }, row.keys, row.previous)

  else
    return keys.new({}, row.keys, row.previous)
  end
end


rediscover_keys = function(name, row, opts)
  return function()
    log("rediscovering keys for ", name)
    return rotate_keys(name, row, nil, nil, nil, opts)
  end
end


local function get_keys(name)
  if kong.configuration.database == "off" then
    return strategy.select(name)
  end

  local cache_strategy = strategies["off"]
  local row = cache_strategy.select(name)

  if not row then
    row = strategy.select(name)
    cache_strategy.store_keys(name, row)
  end

  return row
end


local function load_keys(name, opts)
  local row, err = get_keys(name)
  if err then
    log(err)
  end

  return rotate_keys(name, row, false, nil, nil, opts)
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

      return cycle_aware_deep_copy(res[1])

    else
      log("unable to generate a cache key for introspection")
    end
  end

  return introspect_uri(endpoint, opaque_token, hint, authorization, args, timeout)
end

local function get_all_keys()
  return strategy.select_all_keys()
end

return {
  init_worker   = init_worker,
  load_keys     = load_keys,
  get_keys      = get_keys,
  get_all_keys  = get_all_keys,
  load_consumer = load_consumer,
  rotate_keys   = rotate_keys,
  introspect    = introspect,
  keys          = keys,
  is_rotated_recently = is_rotated_recently,
}
