-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.tools.utils"
local pl_file = require "pl.file"
local cjson = require "cjson"
local pkey = require "resty.openssl.pkey"


local DEFAULT_PADDING = pkey.PADDINGS.RSA_PKCS1_PADDING
local PUBLIC_KEY_OPTS = {
  format = "PEM",
  type = "pu",
}
local PRIVATE_KEY_OPTS = {
  format = "PEM",
  type = "pr",
}


local keyring = require "kong.keyring"


local _M = {}
local _log_prefix = "[keyring cluster] "


local function broadcast_message(t)
  assert(t.host)
  assert(t.keys)

  for _, key in ipairs(t.keys) do
    assert(key.data)
    assert(key.id)
  end

  return cjson.encode(t)
end


local function register_message(t)
  assert(t.host)
  assert(t.pkey)
  assert(type(t.key_ids) == "table" or t.key_ids == "*")

  return cjson.encode(t)
end


-- key references
local pub, priv


-- import/export key references
local envelope_rsa = {}


local function load_envelope_keys(config)
  if config.keyring_private_key then
    local err
    envelope_rsa.priv, err = pl_file.read(config.keyring_private_key)
    if err ~= nil then
      ngx.log(ngx.ERR, "error loading private key: ", err)
    end
  end

  if config.keyring_public_key then
    local err
    envelope_rsa.pub, err = pl_file.read(config.keyring_public_key)
    if err ~= nil then
      ngx.log(ngx.ERR, "error loading public key: ", err)
    end
  end
end


function _M.envelope_key_priv()
  return envelope_rsa.priv
end


function _M.envelope_key_pub()
  return envelope_rsa.pub
end


local generate_node_keys
do
  local KEY_STRENGTH = 2048
  local KEY_OPTS = {
    type = "RSA",
    bits = KEY_STRENGTH,
    exp = 65537
  }

  generate_node_keys = function()
    ngx.log(ngx.DEBUG, _log_prefix, "generating ephemeral node RSA keys (",
            KEY_STRENGTH, ")")

    local key, err = pkey.new(KEY_OPTS)

    if not key then
      error(err)
    end

    pub = key:tostring("public", "PEM")
    priv = key:tostring("private", "PEM")

    return true
  end
end


local function get_public_key()
  assert(pub ~= nil)

  return pub
end
_M.get_public_key = get_public_key


local function local_keyring_read(config)
  if config.keyring_blob_path and config.keyring_private_key then
    local priv, err = pkey.new(pl_file.read(config.keyring_private_key), PRIVATE_KEY_OPTS)
    if err then
      error(err)
    end

    local data = assert(pl_file.read(kong.configuration.keyring_blob_path))

    local decrypted = assert(priv:decrypt(data, DEFAULT_PADDING))

    local keys = cjson.decode(decrypted)

    for k, v in pairs(keys.keys) do
      local ok, err = keyring.keyring_add(k, ngx.decode_base64(v), true)
      if not ok then
        error(err)
      end
    end

    assert(keyring.activate_local(keys.active))
  end
end


local function local_keyring_write(config)
  if config.keyring_blob_path and config.keyring_public_key then
    local pub, err = pkey.new(pl_file.read(kong.configuration.keyring_public_key), PUBLIC_KEY_OPTS)
    if err then
      error(err)
    end

    local data = {
      keys = keyring.get_keys(),
      active = keyring.active_key_id(),
    }

    local data, err = pub:encrypt(cjson.encode(data), DEFAULT_PADDING)
    if err then
      error(err)
    end

    assert(pl_file.write(kong.configuration.keyring_blob_path, data))
  end

  return local_keyring_read(config)
end


function _M.init(config)
  ngx.log(ngx.DEBUG, "generating node keys")
  assert(generate_node_keys())

  load_envelope_keys(config)

  local r, err = kong.db.keyring_meta:each(1)
  if err then
    error(err)
  end

  if r() ~= nil then
    return local_keyring_read(config)
  end

  local opts = {
    ttl     = 10,
    no_wait = true,
  }

  local ok, err = kong.db:cluster_mutex("keyring_bootstrap", opts, function()
    local bytes, err = utils.get_rand_bytes(32)
    if err then
      error(err)
    end

    local id = keyring.new_id()

    local ok, err = keyring.keyring_add(id, bytes)
    if not ok then
      error(err)
    end

    ok, err = keyring.activate(id, true)
    if not ok then
      error(err)
    end
  end)

  if not ok then
    error(err)
  end

  return local_keyring_write(config)
end


function _M.activate_from_cluster_status()
  local k, err = kong.db.keyring_meta:select_existing_active()
  if err then
    return false, err
  end

  local id = k.id

  return keyring.backoff(function(id)
    return keyring.activate_local(id)
  end, nil, id)
end


local function handle_broadcast(data)
  local msg = cjson.decode(data)

  local node_id = kong.node.get_id()
  if msg.host ~= node_id then
    return
  end

  local node_priv, err = pkey.new(priv, PRIVATE_KEY_OPTS)
  if err then
    error("invalid private key: ", err)
  end

  for _, key in ipairs(msg.keys) do
    if keyring.get_key(key.id) then
      ngx.log(ngx.DEBUG, _log_prefix, "already have ", key.id)
    else
      local key_material = ngx.decode_base64(key.data)
      local decrypted = assert(node_priv:decrypt(key_material, DEFAULT_PADDING))

      keyring.keyring_add(key.id, decrypted, true)
    end
  end

  local ok, err = _M.activate_from_cluster_status()
  if not ok then
    ngx.log(ngx.ERR, _log_prefix, err)
  end

  keyring.invalidate_cache()
end


local function handle_register(data)
  local msg = cjson.decode(data)

  -- recipient
  local node_id = msg.host
  local pub_key = msg.pkey
  local key_ids = msg.key_ids

  local node_pub, err = pkey.new(pub_key, PUBLIC_KEY_OPTS)
  if err then
    error("invalid public key: ", err)
  end

  local keys = {}
  local wanted_keys

  if key_ids == '*' then
    wanted_keys = {}
    for id in pairs(keyring.get_keys()) do
      table.insert(wanted_keys, id)
    end
  else
    wanted_keys = key_ids
  end

  ngx.log(ngx.DEBUG, _log_prefix, "furnishing key IDs '",
          table.concat(wanted_keys, ","), "'")

  for _, k in ipairs(wanted_keys) do
    local bytes, err = keyring.get_key(k)
    if err and err ~= "not found" then
      ngx.log(ngx.WARN, _log_prefix, "error in fetching keyring data: ", err)
    end

    if bytes then
      table.insert(keys, {
        id = k,
        data = ngx.encode_base64(node_pub:encrypt(bytes, DEFAULT_PADDING))
      })
    end
  end

  if #keys > 0 then
    local msg = {
      host = node_id,
      keys = keys,
    }

    local ok, err = kong.cluster_events:broadcast("keyring_broadcast",
                                                  broadcast_message(msg))
    if not ok then
      ngx.log(ngx.ERR, _log_prefix, "cluster event broadcast failure: ", err)
    end
  end
end


local function request_missing_keys()
  local node_id = kong.node.get_id()
  local keys = keyring.get_keys()

  local needed_keys = {}

  for row, err in kong.db.keyring_meta:each() do
    if err then
      ngx.log(ngx.ERR, _log_prefix, err)
    end

    if not keys[row.id] then
      table.insert(needed_keys, row.id)
    end
  end

  if #needed_keys > 0 then
    ngx.log(ngx.DEBUG, _log_prefix, "requesting key IDs '",
        table.concat(needed_keys, ","), "'")

    local ok, err = kong.cluster_events:broadcast("keyring_register", register_message({
      host = node_id,
      pkey = pub,
      key_ids = needed_keys,
    }))
    if not ok then
      ngx.log(ngx.ERR, _log_prefix, "cluster event broadcast failure: ", err)
    end
  end
end


function _M.init_worker(config)
  kong.cluster_events:subscribe("keyring_activate", function(data)
    ngx.log(ngx.INFO, _log_prefix, "activating ", data)

    local ok, err = keyring.activate_local(data)
    if not ok then
      ngx.log(ngx.ERR, _log_prefix, err)
    end
  end)

  kong.cluster_events:subscribe("keyring_remove", function(data)
    ngx.log(ngx.INFO, _log_prefix, "removing ", data)

    -- dont rebroadcast
    local ok, err = keyring.keyring_remove(data, true)
    if not ok then
      ngx.log(ngx.ERR, _log_prefix, err)
    end
  end)

  -- inbound keys
  kong.cluster_events:subscribe("keyring_broadcast", handle_broadcast)

  -- requests for keys
  kong.cluster_events:subscribe("keyring_register", handle_register)

  -- make an initial request for keys if necessary (eg if we're not the bootstrap)
  -- then, check in with the cluster regularly
  if ngx.worker.id() == 0 then
    local node_id = kong.node.get_id()

    ngx.timer.at(0, function()
      if next(keyring.get_key_ids()) then
        return
      end

      local ok, err = kong.cluster_events:broadcast("keyring_register", register_message({
        host = node_id,
        pkey = pub,
        key_ids = "*",
      }))
      if not ok then
        ngx.log(ngx.ERR, _log_prefix, "cluster event broadcast failure: ", err)
      end
    end)

    ngx.timer.every(config.db_update_frequency, request_missing_keys)
  end
end


return _M
