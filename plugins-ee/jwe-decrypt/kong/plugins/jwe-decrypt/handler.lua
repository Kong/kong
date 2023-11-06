-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local kong = kong
local fmt = string.format
local get_header = kong.request.get_header
local set_header = kong.service.request.set_header
local meta = require "kong.meta"
local isempty = require "table.isempty"
local lower = string.lower
local sub = string.sub

local EXIT_CODES = {
  ["UNAUTHORIZED"] = 403,
  ["BADREQUEST"] = 400,
}

local ERROR_MESSAGES = {
  ["DECRYPT_ERR"] = "failed to decrypt token",
  ["DECODE_ERR"] = "failed to decode token",
  ["NO_TOKEN_ERR"] = "could not find token",
}

-- check header for known prefix "Bearer"
-- return token without prefix and indication
-- whether bearer token was found
local function check_bearer_header(header)
  if lower(sub(header, 1, 6)) == "bearer" then
    -- start at end of `Bearer` (7) plus (1) for space
    return sub(header, 8), true
  end
  return header, false
end

local JWEDecryptHandler = {}

JWEDecryptHandler.PRIORITY = 1999
JWEDecryptHandler.VERSION = meta.core_version

-- prints log message on configurable level and exists with error code and message
local function log_and_exit(log_level, log_message, exit_code, msg)
  assert(log_message)
  assert(exit_code)
  assert(msg)
  log_level = log_level or "info"
  kong.log[log_level](log_message)
  return kong.response.exit(exit_code, { message = msg })
end

-- callback fn for keys
local function load_keys(cache_key)
  return kong.db.keys:select_by_cache_key(cache_key)
end

-- callback fn for keysets
local function load_keyset_by(name)
  return kong.db.key_sets:select_by_name(name)
end

---Find a key by key id(kid) within key-sets
local function find_key_in_sets(keysets, kid)
  for _, set_name in pairs(keysets) do
    -- load keyset
    local key_sets_cache_key = kong.db.key_sets:cache_key(set_name)
    local key_set, ks_err = kong.cache:get(key_sets_cache_key, nil, load_keyset_by, set_name)
    if not key_set or ks_err then
      local msg = fmt("could not load keyset %s. %s", set_name, ks_err or "")
      kong.log.warn(msg)
      return nil, msg
    end
    -- load key with kid in set.
    local cache_key = kong.db.keys:cache_key({ kid = kid, set = { id = key_set.id } })
    local key, key_cache_err, hit_level = kong.cache:get(cache_key, nil, load_keys, cache_key)
    -- return if found
    if key and not key_cache_err then
      if hit_level ~= 3 then
        kong.vault.update(key)
      end
      return key, nil
    end
  end
  -- no key found in all configured sets
  return nil, fmt("could not find kid %s in configured keysets", kid)
end

function JWEDecryptHandler:access(plugin_conf)
  local jwe = kong.jwe
  -- the key_sets that holds the JWK used for decryption
  local key_sets = plugin_conf.key_sets
  local lookup_header_name = plugin_conf.lookup_header_name
  local forward_header_name = plugin_conf.forward_header_name
  -- defaults to true
  local strict = plugin_conf.strict
  local auth_header, err = get_header(lookup_header_name)
  local bearer_prefix

  if not auth_header then
    kong.log.warn("could not find header: ", lookup_header_name, " (", err, ")")
    -- strict mode requires you to have an auth_header set
    if strict then
      return kong.response.exit(EXIT_CODES.UNAUTHORIZED, { message = ERROR_MESSAGES.NO_TOKEN_ERR })
    end
    -- can't continue without header
    return
  end
  auth_header, bearer_prefix = check_bearer_header(auth_header)

  -- decode token
  local decoded_token, decode_err = jwe:decode(auth_header)
  if type(decoded_token) ~= "table"
      or isempty(decoded_token)
      or not decoded_token
      or decode_err then
    return log_and_exit("err", decode_err or ERROR_MESSAGES.DECODE_ERR,
      EXIT_CODES.BADREQUEST, ERROR_MESSAGES.DECODE_ERR)
  end

  -- check if we have a 'protected' header
  local header = decoded_token.protected or nil
  if not header then
    return log_and_exit("err", "error while docoding: JWE does not contain header",
      EXIT_CODES.BADREQUEST, ERROR_MESSAGES.DECODE_ERR)
  end

  local kid = header.kid
  local enc = header.enc

  -- check if we have the required header fields
  if not kid and enc then
    local msg = "JWE needs to contain jwk kid and enc fields"
    return log_and_exit("err", msg, EXIT_CODES.BADREQUEST, msg)
  end

  -- retrieve key from key sets
  local key, kerr = find_key_in_sets(key_sets, kid)
  if not key or kerr then
    local msg = kerr or "error while retrieving keys"
    return log_and_exit("err", msg, EXIT_CODES.UNAUTHORIZED, ERROR_MESSAGES.DECRYPT_ERR)
  end

  -- get private_key
  local priv_key, privkey_err = kong.db.keys:get_privkey(key)
  if not priv_key or privkey_err then
    local msg = fmt("could not retrieve private key for kid: %s", kid)
    return log_and_exit("err", msg, EXIT_CODES.UNAUTHORIZED, ERROR_MESSAGES.DECRYPT_ERR)
  end

  -- decrypting
  local token, decrypt_err = jwe:decrypt(priv_key, auth_header)
  if not token or decrypt_err then
    local msg = fmt("error decrypting JWE. %s", decrypt_err or ERROR_MESSAGES.DECRYPT_ERR)
    return log_and_exit("err", msg, EXIT_CODES.UNAUTHORIZED, ERROR_MESSAGES.DECRYPT_ERR)
  end

  -- preserve `Bearer` prefix
  if bearer_prefix then
    token = "Bearer " .. token
  end

  -- set decrypted header
  kong.log.debug("setting decrypted JWE to header <", forward_header_name, ">")
  set_header(forward_header_name, token)
end

return JWEDecryptHandler
