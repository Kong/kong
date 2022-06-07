-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local pkey = require "resty.openssl.pkey"
local digest = require "resty.openssl.digest"
local pl_file = require "pl.file"
local to_hex = require("resty.string").to_hex

local _log_prefix = "[keyring] "

local RECOVERY_MARKER = "$ker$1$"

local dummy = function() return true end


local mutex_opts = {
  ttl = 10,
  no_wait = true,
}

local function recovery_encrypt(key_id, key_material)
  local pub_key_path = kong.configuration.keyring_recovery_public_key
  if not pub_key_path then
    return true
  end

  local pub_content, err = pl_file.read(pub_key_path)
  if not pub_content then
    return false, err
  end

  local pub, err = pkey.new(pub_content)
  if not pub then
    return false, err
  end

  local recovery_key_id, err = digest.new("SHA256"):final(pub:tostring("DER"))
  if not recovery_key_id then
    return false, err
  end

  local encrypted, err = pub:encrypt(key_material)
  if not encrypted then
    return false, err
  end
  encrypted = RECOVERY_MARKER .. ngx.encode_base64(encrypted)

  local ok, err = kong.db.keyring_keys:upsert({ id = key_id }, {
    id = key_id,
    recovery_key_id = to_hex(recovery_key_id),
    key_encrypted = encrypted,
  })
  if not ok then
    return false, err
  end

  return true
end


return setmetatable({
  cluster = {
    keyring_add = function(id, key, local_only)
      if local_only then
        return true
      end

      local _, err = kong.db.keyring_meta:upsert(
        {
          id = id
        },
        {
          id = id,
          state = "alive",
        }
      )

      if err then
        return false, err
      end

      local ok, err = recovery_encrypt(id, key)
      if not ok then
        return false, "recovery backup failed: " .. tostring(err)
      end

      return true
    end,

    keyring_remove = function(id, quiet)
      if quiet then
        return true
      end

      local _, err = kong.db.keyring_meta:delete({ id = id })
      if err then
        return false, err
      end

      local ok, err = kong.cluster_events:broadcast("keyring_remove", id)
      if not ok then
        return false, err
      end

      if kong.configuration.keyring_recovery_public_key then
        local _, err = kong.db.keyring_keys:delete({ id = id })
        if err then
          return false, err
        end
      end

      return true
    end,

    activate = function(id)
      return kong.db:cluster_mutex("keyring_activate", mutex_opts, function()
        return kong.db.keyring_meta:activate(id)
      end)
    end,

    recover = function(private_key)
      local result = {
        recovered = {},
        not_recovered = {},
      }

      local priv, err = pkey.new(private_key)
      if not priv then
        return false, err
      elseif not priv:is_private() then
        return false, "recovery needs a private key"
      end

      local recovery_key_id, err = digest.new("SHA256"):final(priv:tostring("DER"))
      if not recovery_key_id then
        return false, err
      end
      recovery_key_id = to_hex(recovery_key_id)

      for row, err in kong.db.keyring_keys:each() do
        if err then
          ngx.log(ngx.ERR, _log_prefix, err)
        elseif row.recovery_key_id ~= recovery_key_id then
          ngx.log(ngx.INFO, _log_prefix, "current recovery key ", recovery_key_id, " won't recover key_id ", row.id,
                  " encrypted by recovery key ", row.recovery_key_id, ", skipping")
        end

        local marker = string.sub(row.key_encrypted, 1, #RECOVERY_MARKER)
        local reminder = string.sub(row.key_encrypted, #RECOVERY_MARKER+1)
        local ciphertext = ngx.decode_base64(reminder)

        if marker ~= RECOVERY_MARKER then
          ngx.log(ngx.ERR, _log_prefix, "unsupported recovery data:", marker)
        elseif not ciphertext then
          ngx.log(ngx.ERR, _log_prefix, "corrupted ciphertext:", reminder)
        else
          local decrypted, err = priv:decrypt(ciphertext)
          if err then
            ngx.log(ngx.ERR, _log_prefix, "unable to decrypt key ", row.id, " err: ", err)
          else
            row.key_encrypted = nil
            row.key = decrypted
            table.insert(result.recovered, row)
            goto recovered
          end
        end

        if row and row.id then
          table.insert(result.not_recovered, row.id)
        end
::recovered::
      end

      return result
    end,

  },
}, {
  __index = function()
    return setmetatable({}, { __index = function() return dummy end })
  end,
})
