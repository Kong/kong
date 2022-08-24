-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local keyring = require "kong.keyring"
local keyring_cluster = require "kong.keyring.strategies.cluster"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local cipher = require "resty.openssl.cipher"
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


local function cluster_only()
  if kong.configuration.keyring_strategy ~= "cluster" then
    return kong.response.exit(400, {
      error = "endpoint only supported for 'cluster' strategy"
    })
  end
end


return {
  ["/keyring"] = {
    GET = function(self, db, helpers, parent)
      local keyring = {
        ids = keyring.get_key_ids(),
        active = keyring.active_key_id(),
      }

      return kong.response.exit(200, keyring)
    end,
  },

  ["/keyring/active"] = {
    GET = function(self, db, helpers, parent)
      local k, err, id = keyring.active_key()
      if not k then
        return kong.response.exit(err == "active key not found" and 503 or 500,
                                  { error = err })
      end

      return kong.response.exit(200, { id = id })
    end,
  },

  ["/keyring/export"] = {
    before = cluster_only,

    POST = function(self, db, helpers, parent)
      if not kong.configuration.keyring_public_key then
        return kong.response.exit(500, { error = "missing backup public key" })
      end

      local rsa, err = pkey.new(keyring_cluster.envelope_key_pub(), PUBLIC_KEY_OPTS)
      if err then
        return kong.response.exit(500, { error = err })
      end

      local key = utils.get_rand_bytes(32, true)
      local nonce = utils.get_rand_bytes(12, true)

      local cp, err = cipher.new("aes-256-gcm")
      if not cp then
        return kong.response.exit(500, { error = err })
      end
      local c, err = cp:encrypt(key, nonce, cjson.encode({
        keys = keyring.get_keys(),
        active = keyring.active_key_id(),
      }))
      if err then
        return kong.response.exit(500, { error = err })
      end

      local k_enc, err = rsa:encrypt(key, DEFAULT_PADDING)
      if err then
        return kong.response.exit(500, { error = err })
      end

      local m = {
        k = ngx.encode_base64(k_enc),
        n = ngx.encode_base64(nonce),
        d = ngx.encode_base64(c),
      }

      return kong.response.exit(200, { data = ngx.encode_base64(cjson.encode(m)) } )
    end,
  },

  ["/keyring/import"] = {
    before = cluster_only,

    POST = function(self, db, helpers, parent)
      local d = self.params.data
      local data = cjson.decode(ngx.decode_base64(d))

      -- decrypt the wrapped secret
      local rsa, err = pkey.new(keyring_cluster.envelope_key_priv(), PRIVATE_KEY_OPTS)
      if err then
        return kong.response.exit(500, { error = err })
      end


      local nonce = ngx.decode_base64(data.n)
      local key, err = rsa:decrypt(ngx.decode_base64(data.k), DEFAULT_PADDING)
      if err then
        return kong.response.exit(500, { error = err })
      end

      local cp, err = cipher.new("aes-256-gcm")
      if err then
        return kong.response.exit(500, { error = err })
      end
      cp:decrypt(key, nonce)

      local plaintext = cp:update(ngx.decode_base64(data.d))
      local imported_keyring = cjson.decode(plaintext)

      for id, key in pairs(imported_keyring.keys) do
        local ok = keyring.keyring_add(id, ngx.decode_base64(key), true)
        if not ok then
          return kong.response.exit(500, { error = "failure to add to keyring" })
        end
      end

      local ok, err = keyring.activate(imported_keyring.active)
      if not ok then
        return kong.response.exit(500, { error = err })
      end

      keyring.invalidate_cache()

      local k = {
        ids = keyring.get_key_ids(),
        active = keyring.active_key_id(),
      }

      return kong.response.exit(200, k)
    end,
  },

  ["/keyring/import/raw"] = {
    before = cluster_only,

    POST = function(self, db, helpers, parent)
      local id = self.params.id
      local data = self.params.data

      if type(id) ~= "string" or type(data) ~= "string" then
        return kong.response.exit(400, { error = "missing 'id' or 'data' params" })
      end

      local bytes = ngx.decode_base64(data)
      if #bytes ~= 32 then
        return kong.response.exit(400, { error = "key must be 32 bytes" })
      end

      local ok, err = keyring.keyring_add(id, bytes)
      if err then
        return kong.response.exit(500, { error = err })
      end

      keyring.invalidate_cache()

      return kong.response.exit(ok and 201 or 500, err)
    end,
  },

  ["/keyring/generate"] = {
    before = cluster_only,

    POST = function(self, db, helpers, parent)
      local bytes, err = utils.get_rand_bytes(32)
      if err then
        error(err)
      end

      local id = keyring.new_id()

      local ok = keyring.keyring_add(id, bytes)
      if not ok then
        return kong.response.exit(500, { error = "failure to add to keyring" })
      end

      return kong.response.exit(201, { id = id, key = ngx.encode_base64(bytes) })
    end,
  },

  ["/keyring/activate"] = {
    before = cluster_only,

    POST = function(self, db, helpers, parent)
      local k = self.params.key

      local ok, err = keyring.activate(k)
      if not ok then
        return kong.response.exit(500, { error = err })
      end

      return kong.response.exit(204)
    end,
  },

  ["/keyring/remove"] = {
    before = cluster_only,

    POST = function(self, db, helpers, parent)
      local k = self.params.key

      local ok, err = keyring.keyring_remove(k)
      if not ok then
        return kong.response.exit(500, { error = err })
      end

      return kong.response.exit(204)
    end,
  },

  ["/keyring/recover"] = {
    before = cluster_only,

    POST = function(self, db, helpers, parent)
      local priv = self.params.recovery_private_key

      local result, err = keyring.recover(priv)
      if err then
        return kong.response.exit(500, { error = err })
      end

      keyring.invalidate_cache()

      return kong.response.exit(200, {
        message = string.format("successfully recovered %d keys", #result.recovered),
        recovered = result.recovered,
        not_recovered = result.not_recovered,
      })
    end,
  },

  ["/keyring/vault/sync"] = {
    POST = function(self, db, hekpers, parent)
      local token = self.params.token or kong.configuration.keyring_vault_token

      local vault_keyring = require "kong.keyring.strategies.vault"
      local ok, err = vault_keyring.sync(token)
      if not ok then
        return kong.response.exit(500, { error = err })
      end

      return kong.response.exit(204)
    end,
  }
}
