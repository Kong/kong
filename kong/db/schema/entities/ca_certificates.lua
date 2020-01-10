local typedefs = require "kong.db.schema.typedefs"
local openssl_x509 = require "resty.openssl.x509"

return {
  name        = "ca_certificates",
  primary_key = { "id" },

  fields = {
    { id = typedefs.uuid, },
    { created_at = typedefs.auto_timestamp_s },
    { cert = typedefs.certificate { required = true, unique = true, }, },
    { tags = typedefs.tags },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "cert", },
      fn = function(entity)
        local seen = false
        for _ in string.gmatch(entity.cert, "%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-") do
          if seen then
            return nil, "please submit only one certificate at a time"
          end

          seen = true
        end

        local cert = openssl_x509.new(entity.cert)
        local not_after = cert:get_not_after()
        local now = ngx.time()

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
