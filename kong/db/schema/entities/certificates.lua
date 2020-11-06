-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local openssl_pkey = require "resty.openssl.pkey"
local openssl_x509 = require "resty.openssl.x509"

return {
  name        = "certificates",
  primary_key = { "id" },
  dao         = "kong.db.dao.certificates",
  workspaceable = true,

  fields = {
    { id = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { cert           = typedefs.certificate { required = true }, },
    { key            = typedefs.key         { required = true, encrypted = true }, },
    { tags           = typedefs.tags },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "cert", "key" },
      fn = function(entity)
        local cert = openssl_x509.new(entity.cert)
        local key = openssl_pkey.new(entity.key)

        if cert:get_pubkey():to_PEM() ~= key:to_PEM("public") then
          return nil, "certificate does not match key"
        end

        return true
      end,
    } }
  }
}
