local typedefs = require "kong.db.schema.typedefs"
local openssl_pkey = require "openssl.pkey"
local openssl_x509 = require "openssl.x509"

return {
  name = "ca",

  -- Cassandra *requires* a primary key.
  -- To keep it happy we add a superfluous boolean column that is always true.
  primary_key = { "pk" },

  fields = {
    { pk = {
      type = "boolean",
      default = true,
      custom_validator = function(pk)
        if pk ~= true then
          return nil, "pk must be true"
        end
        return true
      end,
    } },
    { cert = typedefs.certificate { required = true } },
    { key = typedefs.key { required = true } },
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
