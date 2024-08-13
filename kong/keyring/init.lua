-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.tools.utils"
local ngx_re = require "ngx.re"
local keyring_utils = require "kong.keyring.utils"
local cipher = require "resty.openssl.cipher"
local to_hex = require("resty.string").to_hex

local ngx = ngx
local get_phase = ngx.get_phase

local has_return_encrypted = false

local _M = {}
local _log_prefix = "[keyring] "


local CRYPTO_MARKER = "$ke$1$"
local SEPARATOR = "-"
local ALGORITHM = "aes-256-gcm"

local function from_hex(s)
  return s:gsub('..', function(cc) return string.char(tonumber(cc, 16)) end)
end

local function is_encrypted(s)
  return s:sub(1, #CRYPTO_MARKER) == CRYPTO_MARKER
end

function _M.value_is_encrypted(s)
  return type(s) == "string" and is_encrypted(s)
end

local strategy
function _M.set_strategy(s)
  strategy = s
end


local function backoff(cb, opts, ...)
  local bit = require "bit"

  opts = opts or {}

  local exp = 0
  local max = opts.max or kong.configuration.db_update_frequency / 2
  local max_iter = opts.max_iter or 10
  local variance = opts.variance or 20

  local function s()
    local n = bit.lshift(1, exp)
    exp = exp + 1
    return (math.min(n, max) * (math.random(100 - variance, 100 + variance) / 100))
  end

  local last_err

  while true do
    if exp > max_iter then
      return nil, last_err or "timeout"
    end

    local perr = table.pack(cb(...))

    local ok = perr[1]
    if ok then
      return table.unpack(perr)
    end

    last_err = perr[2]
    ngx.sleep(s())
  end
end
_M.backoff = backoff


function _M.encrypt(p)
  if not kong.configuration.keyring_enabled then
    return p
  end

  if not p then
    return p
  end

  assert(type(p) == "string")

  -- encrypted in the first place, dont re-run it
  if is_encrypted(p) then
    return p
  end

  local key, err, id = backoff(_M.active_key)
  if err then
    error(err)
  end

  local nonce = utils.get_rand_bytes(12, true)

  -- this can be cached per worker if it's becoming bottleneck
  local cp, err = cipher.new(ALGORITHM)
  if err then
    error(err)
  end

  local _
  _, err = cp:init(key, nonce, {
    is_encrypt = true,
  })
  if err then
    error(err)
  end

  local c
  c, err = cp:update(p)
  if err then
    error(err)
  end

  return CRYPTO_MARKER .. SEPARATOR .. id .. SEPARATOR .. to_hex(nonce) ..
         SEPARATOR .. to_hex(c)
end


function _M.decrypt(c)
  if not kong.configuration.keyring_enabled then
    return c
  end

  if not c then
    return c
  end

  local origin_c = c

  assert(type(c) == "string")

  -- wasnt encrypted in the first place
  if not is_encrypted(c) then
    return c
  end

  c = c:sub(#CRYPTO_MARKER + 2)

  local id, nonce, ciphertext
  local r = ngx_re.split(c, SEPARATOR, "oj")

  assert(r[1])
  assert(r[2])
  assert(r[3])

  id = r[1]
  nonce = from_hex(r[2])
  ciphertext = from_hex(r[3])

  if id ~= _M.active_key_id() then
    ngx.log(ngx.DEBUG, _log_prefix, "using non-active key (", id, ") to read")
  end

  local phase = get_phase()
  if phase == "init" or phase == "init_worker" then
    local key, err = _M.get_key(id)
    -- return the ciphertext only if err is key not found.
    -- ensure the ciphertext doesn't be returned after soft reload(e.g. kong reload).
    if not key and err == "key not found" then
      has_return_encrypted = true
      return origin_c
    end
  end

  local key, err = backoff(_M.get_key, nil, id)
  if not key then
    error(err)
  end

  -- this can be cached per worker if it's becoming bottleneck
  local cp, err = cipher.new(ALGORITHM)
  if err then
    error(err)
  end

  local _
  _, err = cp:init(key, nonce, {
    is_encrypt = false,
  })
  if err then
    error(err)
  end

  -- don't call final as we are not providing the tag
  local plaintext
  plaintext, err = cp:update(ciphertext)
  if err then
    error(err)
  end

  return plaintext
end


function _M.keyring_add(id, key, local_only)
  local ok, err = ngx.shared.kong_keyring:set(id, key)
  if not ok then
    return false, err
  end

  ok, err = keyring_utils[strategy].keyring_add(id, key, local_only)
  if not ok then
    return false, err
  end

  return true
end


function _M.keyring_remove(id, quiet)
  local active_id = _M.active_key_id()
  if id == active_id then
    return false, "cannot remove active key"
  end

  ngx.shared.kong_keyring:delete(id)

  local ok, err = keyring_utils[strategy].keyring_remove(id, quiet)
  if not ok then
    return false, err
  end

  return true
end


function _M.get_key_ids()
  local keys = ngx.shared.kong_keyring:get_keys()
  for i = 1, #keys do
    if keys[i] == "active" then
      table.remove(keys, i)
    end
  end
  return keys
end


function _M.get_keys(raw)
  local keys = _M.get_key_ids()
  local t = {}

  for _, key in ipairs(keys) do
    local keyring = ngx.shared.kong_keyring:get(key)

    if raw then
      t[key] = keyring
    else
      t[key] = ngx.encode_base64(keyring)
    end
  end

  return t
end


function _M.get_key(id)
  local k, err = ngx.shared.kong_keyring:get(id)
  if not k then
    return nil, err and err or "key not found"
  end

  return k
end


function _M.active_key()
  local id, err = _M.active_key_id()
  if not id then
    return nil, err
  end

  local key
  key, err = _M.get_key(id)
  if not key then
    return nil, err ~= "key not found" and err or "active key not found"
  end

  return key, nil, id
end


function _M.active_key_id()
  local id, err = ngx.shared.kong_keyring:get("active")
  if not id then
    return nil, err and err or "active key id not found"
  end

  return id
end


function _M.activate_local(id)
  local keyring = _M.get_keys()

  if not keyring[id] then
    return false, "not found"
  end

  local ok, err = ngx.shared.kong_keyring:set("active", id)
  if not ok then
    return false, err
  end

  ngx.log(ngx.INFO, _log_prefix, "activating key '", id, "'")

  if kong and kong.worker_events then
    kong.worker_events.post_local("keyring", "activate_local")
  end

  return true
end


function _M.activate(id, no_activate)
  local ok, err = _M.activate_local(id)
  if not ok then
    return false, err
  end

  ok, err = keyring_utils[strategy].activate(id)
  if not ok then
    return false, err
  end

  if not no_activate then
    ok, err = kong.cluster_events:broadcast("keyring_activate", id)
    if not ok then
      ngx.log(ngx.ERR, _log_prefix, "cluster event broadcast failure: ", err)
      return false
    end
  end

  return true
end


function _M.new_id()
  return utils.random_string():sub(1, 8)
end

-- Recover cluster-level encryption keys through decoding the table in the database.
function _M.recover(recv_key)
  local result, err = keyring_utils[strategy].recover(recv_key)
  if err then
    return nil, err
  end

  local recovered_ids = {}
  local _
  local push_config

  if #result then
    for i, key in ipairs(result.recovered) do
      ngx.log(ngx.ERR, "[keyring] storing ", key.id, " to recovery table")
      _, err = _M.keyring_add(key.id, key.key, true) -- local_only
      if err then
        return nil, "failed adding recovered key: " .. err
      end

      recovered_ids[i] = key.id
      push_config = true
    end
  end

  if push_config then
    kong.worker_events.post_local("keyring", "recover")
  end

  result.recovered = recovered_ids -- only return ids to caller, hide the key value

  return result
end

-- keyring returns the encrypted data to outside in init* phase for some reasons
-- the outside might store the encrypted data to the cache (e.g. plugin_iterator stores
-- the plugin entity to the cache)
-- this workaround function removes the encrypted data by purging the core_cache
function _M.invalidate_cache()
  if has_return_encrypted then
    ngx.log(ngx.DEBUG, _log_prefix, "purge core_cache")
    kong.core_cache:purge()
    has_return_encrypted = false
  end
end

return _M
