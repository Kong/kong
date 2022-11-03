-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pkey = require("resty.openssl.pkey")
local fmt = string.format

local keys = {}


function keys:truncate()
  return self.super.truncate(self)
end


function keys:select(primary_key, options)
  return self.super.select(self, primary_key, options)
end


function keys:page(size, offset, options)
  return self.super.page(self, size, offset, options)
end


function keys:each(size, options)
  return self.super.each(self, size, options)
end


function keys:insert(entity, options)
  return self.super.insert(self, entity, options)
end


function keys:update(primary_key, entity, options)
  return self.super.update(self, primary_key, entity, options)
end


function keys:upsert(primary_key, entity, options)
  return self.super.upsert(self, primary_key, entity, options)
end


function keys:delete(primary_key, options)
  return self.super.delete(self, primary_key, options)
end


function keys:select_by_cache_key(cache_key, options)
  return self.super.select_by_cache_key(self, cache_key, options)
end


function keys:select_by_kid(unique_value, options)
  return self.super.select_by_kid(self, unique_value, options)
end


function keys:update_by_kid(unique_value, entity, options)
  return self.super.update_by_kid(self, unique_value, entity, options)
end


function keys:upsert_by_kid(unique_value, entity, options)
  return self.super.upsert_by_kid(self, unique_value, entity, options)
end


function keys:delete_by_kid(unique_value, options)
  return self.super.delete_by_kid(self, unique_value, options)
end

function keys:page_for_set(foreign_key, size, offset, options)
  return self.super.page_for_set(self, foreign_key, size, offset, options)
end


function keys:each_for_set(foreign_key, size, options)
  return self.super.each_for_set(self, foreign_key, size, options)
end

function keys:cache_key(kid, set_name)
  if not kid then
    return nil, "kid must exist"
  end
  if type(kid) == "table" then
    kid = kid.kid
  end
  if not set_name then
    set_name = ""
  end
  if type(set_name) == "table" then
    set_name = set_name.name
  end
  -- ignore ws_id, kid+set is unique
  return fmt("keys:%s:%s", tostring(kid), set_name)
end

-- load to lua-resty-openssl pkey module
local function _load_pkey(key, part)
  local pk, err
  local part_to_field = {
    ["public"] = "public_key",
    ["private"] = "private_key",
  }
  part = assert(part_to_field[part])
  if key.jwk then
    pk, err = pkey.new(key.jwk, { format = "JWK" })
  end
  if key.pem then
    if not key.pem[part] then
      return nil, fmt("%s key not found.", part)
    end
    pk, err = pkey.new(key.pem[part], { format = "PEM" })
  end
  if not pk then
    return nil, "could not load pkey. " .. err
  end
  return pk
end

local function _key_format(key)
  -- no nil checks needed. schema validation ensures on of these
  -- entries to be present.
  if key.jwk then
    return "JWK"
  end
  if key.pem then
    return "PEM"
  end
end

local function _get_key(key, part)
  if part ~= "public" and part ~= "private" then
    return nil, "part needs to be public or private"
  end
  -- pkey expects uppercase formats
  local k_fmt = _key_format(key)

  local pk, err = _load_pkey(key, part)
  if not pk or err then
    return nil, err
  end
  return pk:tostring(part, k_fmt)
end

-- getter for public key
function keys:get_pubkey(key)
  return _get_key(key, "public")
end

-- getter for private key
function keys:get_privkey(key)
  return _get_key(key, "private")
end


return keys
