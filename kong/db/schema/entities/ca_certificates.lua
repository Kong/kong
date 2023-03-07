local typedefs      = require "kong.db.schema.typedefs"
local openssl_x509  = require "resty.openssl.x509"

local find          = string.find
local ngx_time      = ngx.time
local to_hex        = require("resty.string").to_hex

local CERT_TAG      = "-----BEGIN CERTIFICATE-----"
local CERT_TAG_LEN  = #CERT_TAG

return {
  name        = "ca_certificates",
  primary_key = { "id" },

  fields = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { cert = typedefs.certificate { required = true }, },
    { cert_digest = { type = "string", unique = true }, },
    { tags = typedefs.tags },
  },

  transformations = {
    {
      input = { "cert" },
      on_write = function(cert)
        local digest = openssl_x509.new(cert):digest("sha256")
        if not digest then
          return nil, "cannot create digest value of certificate"
        end
        return { cert_digest = to_hex(digest) }
      end,
    },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "cert", },
      fn = function(entity)
        local cert = entity.cert

        local seen = find(cert, CERT_TAG, 1, true)
        if seen and find(cert, CERT_TAG, seen + CERT_TAG_LEN + 1, true) then
          return nil, "please submit only one certificate at a time"
        end

        cert = openssl_x509.new(cert)

        local not_after = cert:get_not_after()
        local now = ngx_time()

        if not_after < now then
          return nil, "certificate expired, \"Not After\" time is in the past"
        end

        if not cert:get_basic_constraints("CA") then
          return nil, "certificate does not appear to be a CA because " ..
                      "it is missing the \"CA\" basic constraint"
        end

        return true
      end,
    } }
  }
}
