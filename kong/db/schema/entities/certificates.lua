local typedefs = require "kong.db.schema.typedefs"
local openssl_pkey = require "openssl.pkey"
local openssl_x509 = require "openssl.x509"

return {
  name        = "certificates",
  primary_key = { "id" },
  dao         = "kong.db.dao.certificates",

  fields = {
    { id = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { cert           = typedefs.certificate { required = true }, },
    { key            = typedefs.key         { required = true }, },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "cert", "key" },
      fn = function(entity)
        local cert = openssl_x509.new(entity.cert)
        local key = openssl_pkey.new(entity.key)

        if cert:getPublicKey():toPEM() ~= key:toPEM("public") then
          return nil, "certificate does not match key"
        end

        return true
      end,
    } }
  }
}
