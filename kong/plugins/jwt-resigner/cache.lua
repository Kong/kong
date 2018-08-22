require "kong.plugins.jwt-resigner.env"


local singletons = require "kong.singletons"
local timestamp  = require "kong.tools.timestamp"
local utils      = require "kong.tools.utils"
local jwks       = require "kong.openid-connect.jwks"
local keys       = require "kong.openid-connect.keys"
local log        = require "kong.plugins.jwt-resigner.log"
local json       = require "cjson.safe"


local find = string.find
local time = ngx.time
local type = type


local rediscover_keys


local function load_keys_db(name)
  log("loading jwks from database for ", name)

  local row, err

  if utils.is_valid_uuid(name) then
    row, err = singletons.dao.jwt_resigner_jwks:find({ id = name })

  else
    row, err = singletons.dao.jwt_resigner_jwks:find_all({ name = name })
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

      row, err = singletons.dao.jwt_resigner_jwks:insert({
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

        row, err = singletons.dao.jwt_resigner_jwks:update(data, id)

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

      row, err = singletons.dao.jwt_resigner_jwks:insert({
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

      row, err = singletons.dao.jwt_resigner_jwks:update(data, id)
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
  local cache_key = singletons.dao.jwt_resigner_jwks:cache_key(name)
  local row, err = singletons.cache:get(cache_key, nil, load_keys_db, name)

  if err then
    log(err)
  end

  return rotate_keys(name, row, false)
end


return {
  load_keys   = load_keys,
  rotate_keys = rotate_keys,
}
