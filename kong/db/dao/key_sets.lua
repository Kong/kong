-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http         = require "resty.http"
local json = require "cjson"
local timer_every = ngx.timer.every
local jwk = require "kong.pdk.jwk".new()

-- Check keys every 10 minutes
local ROTATION_TIMER = 3600

local key_sets = {}

--- Fetches a set of JWKs (JSON Web Keys) from a URL and returns them as an array.
---
--- @param url string The URL of the JWKs endpoint to fetch.
---
--- @return table|nil - An array of JWKs if the fetch is successful, or nil if it fails.
--- @return string|nil - An error message if the fetch fails, or nil if it succeeds.
local function load_jwks(url)
  local params = {
    keepalive  = true,
    ssl_verify = false,
  }

  local httpc = http.new()
  if not url or type(url) == "userdata" then
    return nil, "need url, can't be userdata"
  end
  local res = httpc:request_uri(url, params)
  if not res then
    local err
    res, err = httpc:request_uri(url)
    if not res then
      return nil, err
    end
  end

  local status = res.status
  local body = res.body

  -- Check if the HTTP response status code is 200 (OK)
  if status ~= 200 then
    return nil, "invalid status code received from the jwks endpoint (" .. status .. ")"
  end

  if body and body ~= "" then
    -- Parse the HTTP response body as JSON
    local jwks, err = json.decode(body)
    -- Check if the JSON data could be parsed successfully
    if not jwks then
      return nil, "unable to json decode jwks endpoint response (" .. err .. ")"
    end

    -- Check if the parsed JSON data conforms to the JWKS format
    if type(jwks) ~= "table" then
      return nil, "invalid jwks endpoint response received from the jwks endpoint"
    end

    -- Return the parsed JWKS keys and the HTTP response headers
    return jwks.keys, nil
  end

  return nil, "jwks endpoint did not return response body"
end



--- Rotate keys for the given `key_entity_data`.
-- Retrieves the jwks from the `jwks_url` specified in the `key_entity_data`,
-- and updates or inserts the keys in the database,
-- based on the `kid` value and `set` name in the jwks.
-- @param key_entity_data A table containing the key entity data with the `jwks_url` and `set` name
-- @return success A boolean indicating whether the key rotation succeeded
-- @return error An error message in case of failure, or nil in case of success
function key_sets:rotate(key_entity_data)
  local key_set_data = key_entity_data
  local jwks_url = key_set_data.jwks_url
  -- Check if `jwks_url` is present in `key_entity_data`
  -- If not or if it is a `userdata`, return an error
  if not jwks_url or type(jwks_url) == "userdata" then
    return true, "jwks url is required to rotate keys"
  end
  -- Retrieve the jwks from the `jwks_url` using the `load_jwks` function
  local keyset, error = load_jwks(jwks_url)
  if not keyset then
    -- the endpoint did not return any keys, when the `jwks_url` is set
    return false, error
  end
  -- Iterate through each `jwk` in the `keyset`
  for _, remote_key in ipairs(keyset) do
    -- Generate a `cache_key` for the current `jwk` and `set`
    local cache_key, cache_key_err  = self.db.keys:cache_key({kid = remote_key.kid, set = key_set_data })
    if not cache_key then
      -- creating a cache-key is required, hard fail if not possible
      return false, cache_key_err
    end
    -- Select the key from the database using the `cache_key`
    local key, select_err = self.db.keys:select_by_cache_key(cache_key)
    if select_err then
      return false, select_err
    end
    local remote_jwk_json = json.encode(remote_key)
    -- Create a `key_entity` table containing the `jwk` information
    local key_entity = {
      kid = remote_key.kid, -- extracted `kid` attribute from remote key
      set = key_set_data, -- key-set data
      jwk = remote_jwk_json, -- json encoded jwk fetched from the remote resource
    }
    -- if key existed in the database
    if key then
      local remote_jwk = jwk.new(remote_key)
      local jwk_from_db = jwk.new(json.decode(key.jwk))
      -- check if key content has changed, update it
      -- compare the two keys attribute by attribute
      if jwk_from_db ~= remote_jwk then
        -- `pem` is required to be set
        key_entity.pem = key.pem or ngx.null
        local ok, update_err = self.db.keys:update({id = key.id}, key_entity)
        if not ok then
          return false, update_err
        end
      end
    end
    -- if key does not exists, create it
    if not key then
      local ok, insert_err = self.db.keys:insert(key_entity)
      if not ok then
        -- insertion failed, hard stop
        return false, insert_err
      end
    end
  end
  return true
end

function key_sets:truncate()
  return self.super.truncate(self)
end


function key_sets:select(primary_key, options)
  return self.super.select(self, primary_key, options)
end


function key_sets:page(size, offset, options)
  return self.super.page(self, size, offset, options)
end


function key_sets:each(size, options)
  return self.super.each(self, size, options)
end

function key_sets:start_rotation_timer()
  kong.log.notice("starting key rotation timer")
  return timer_every(ROTATION_TIMER, self.rotate_all)
end

-- This method should only be called in a timer-context
function key_sets.rotate_all(premature)
  if premature then
    return true
  end
  for key_set, err in kong.db.key_sets:each() do
    if err then
      return nil, kong.db.errors:schema_violation({"could not load key_sets"})
    end
    local ok, rotate_err = kong.db.key_sets:rotate(key_set)
    if not ok then
      kong.log.warn("error while loading keys from remote resource")
      return nil, rotate_err, kong.db.errors:schema_violation({"could not retrieve keys from the remote resource from"})
    end
  end
end

function key_sets:insert(entity, options)
  local key_set, err, err_t = self.super.insert(self, entity, options)
  local ok, rotate_err = kong.db.key_sets:rotate(key_set)
  if not ok then
    -- rotation is only triggered when a `jwks_url` is present.
    -- a failure indicates an actual failure.
    kong.log.warn("error while loading keys from remote resource")
    return nil, rotate_err, kong.db.errors:schema_violation({"could not retrieve keys from the remote resource"})
  end
  return key_set, err, err_t
end

function key_sets:update(primary_key, entity, options)
  local key_set, err, err_t = self.super.update(self, primary_key, entity, options)
  local ok, rotate_err = kong.db.key_sets:rotate(key_set)
  if not ok then
    -- rotation is only triggered when a `jwks_url` is present.
    -- a failure indicates an actual failure.
    kong.log.warn("error while loading keys from remote resource")
    return nil, rotate_err, kong.db.errors:schema_violation({"could not retrieve keys from the remote resource"})
  end
  return key_set, err, err_t
end


function key_sets:upsert(primary_key, entity, options)
  local key_set, err, err_t = self.super.upsert(self, primary_key, entity, options)
  local ok, rotate_err = kong.db.key_sets:rotate(key_set)
  if not ok then
    -- rotation is only triggered when a `jwks_url` is present.
    -- a failure indicates an actual failure.
    kong.log.warn("error while loading keys from remote resource")
    return nil, rotate_err, kong.db.errors:schema_violation({"could not retrieve keys from the remote resource"})
  end
  return key_set, err, err_t
end


function key_sets:delete(primary_key, options)
  return self.super.delete(self, primary_key, options)
end

function key_sets:select_by_name(unique_value, options)
  return self.super.select_by_name(self, unique_value, options)
end

return key_sets
