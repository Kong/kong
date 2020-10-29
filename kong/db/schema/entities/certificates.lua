local typedefs = require "kong.db.schema.typedefs"
local openssl_pkey = require "resty.openssl.pkey"
local openssl_x509 = require "resty.openssl.x509"


local type = type


return {
  name        = "certificates",
  primary_key = { "id" },
  dao         = "kong.db.dao.certificates",
  workspaceable = true,

  fields = {
    { id = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { cert           = typedefs.certificate { required = true }, },
    { key            = typedefs.key         { required = true }, },
    { cert_alt       = typedefs.certificate { required = false }, },
    { key_alt        = typedefs.key         { required = false }, },
    { tags           = typedefs.tags },
  },

  entity_checks = {
    { mutually_required = { "cert_alt", "key_alt" } },
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
    } },
    { custom_entity_check = {
      field_sources = { "cert_alt", "key_alt" },
      fn = function(entity)
        if type(entity.cert_alt) == "string" and type(entity.key_alt) == "string" then
          local cert_alt = openssl_x509.new(entity.cert_alt)
          local key_alt = openssl_pkey.new(entity.key_alt)

          if cert_alt:get_pubkey():to_PEM() ~= key_alt:to_PEM("public") then
            return nil, "alternative certificate does not match key"
          end
        end

        return true
      end,
    } },
    { custom_entity_check = {
      field_sources = { "cert", "cert_alt" },
      fn = function(entity)
        if type(entity.cert) == "string" and type(entity.cert_alt) == "string" then
          local cert = openssl_x509.new(entity.cert)
          local cert_alt = openssl_x509.new(entity.cert_alt)
          local cert_type = cert:get_pubkey():get_key_type()
          local cert_alt_type = cert_alt:get_pubkey():get_key_type()
          if cert_type.id == cert_alt_type.id then
            return nil, "certificate and alternative certificate need to have " ..
                        "different type (e.g. RSA and ECDSA), the provided " ..
                        "certificates were both of the same type"
          end
        end

        return true
      end,
    } },
  }
}
