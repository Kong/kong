require "kong.plugins.jwt-signer.env"


local singletons  = require "kong.singletons"
local timestamp   = require "kong.tools.timestamp"
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
local time        = ngx.time
local find        = string.find
local type        = type


local rediscover_keys


local function load_keys_db(name)
  log("loading jwks from database for ", name)

  local row, err

  if utils.is_valid_uuid(name) then
    row, err = singletons.dao.jwt_signer_jwks:find({ id = name })

  else
    row, err = singletons.dao.jwt_signer_jwks:find_all({ name = name })
    if row then
      row = row[1]
    end
  end

  return row, err
end


local function rotate_keys(name, row, update, force)
  local err
  local now = timestamp.get_utc_ms()

  if find(name, "https://", 1, true) == 1 or find(name, "http://", 1, true) == 1 then
    if not row then
      log("loading jwks from ", name)

      row, err = keys.load(name, { ssl_verify = false, unwrap = true, json = true })
      if not row then
        return nil, err
      end

      row, err = singletons.dao.jwt_signer_jwks:insert({
        name       = name,
        keys       = row,
        created_at = now,
        updated_at = now,
      })

      if not row then
        return nil, err
      end

    elseif update ~= false then
      local updated_at = row.updated_at or 0

      if not force and now - updated_at < 300000 then
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

        row, err = singletons.dao.jwt_signer_jwks:update(data, id)

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

      row, err = singletons.dao.jwt_signer_jwks:insert({
        name       = name,
        keys       = row,
        created_at = now,
        updated_at = now,
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

      row, err = singletons.dao.jwt_signer_jwks:update(data, id)
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
  local cache_key = singletons.dao.jwt_signer_jwks:cache_key(name)
  local row, err = singletons.cache:get(cache_key, nil, load_keys_db, name)

  if err then
    log(err)
  end

  return rotate_keys(name, row, false)
end


local function introspect_uri(endpoint, opaque_token, hint, authorization, args)
  local options = {
    token_introspection_endpoint = endpoint,
    ssl_verify                   = false,
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


local function introspect_uri_cache(endpoint, opaque_token, hint, authorization, args, now)
  log("introspecting token with ", endpoint)

  local token_info, err = introspect_uri(endpoint, opaque_token, hint, authorization, args)
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


local function introspect(endpoint, opaque_token, hint, authorization, args, cache)
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
      local res, err = singletons.cache:get(cache_key,
                                            nil,
                                            introspect_uri_cache,
                                            endpoint,
                                            opaque_token,
                                            hint,
                                            authorization,
                                            args_table or args,
                                            now)

      if not res then
        return nil, err or "unable to introspect token"
      end

      local exp = res[2]
      if exp and now > exp then
        singletons.cache:invalidate(cache_key)
        return introspect_uri(endpoint, opaque_token, hint, authorization, args_table or args)
      end

      return tablex.deepcopy(res[1])

    else
      log("unable to generate a cache key for introspection")
    end
  end

  return introspect_uri(endpoint, opaque_token, hint, authorization, args)
end


return {
  load_keys   = load_keys,
  rotate_keys = rotate_keys,
  introspect  = introspect,
}
