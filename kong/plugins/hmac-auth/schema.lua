-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


local ALGORITHMS = {
  "hmac-sha256",
  "hmac-sha384",
  "hmac-sha512",
}
if not (_G.kong and kong.configuration and kong.configuration.fips) then
  table.insert(ALGORITHMS, 1, "hmac-sha1")
end


return {
  name = "hmac-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http_and_ws },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { hide_credentials = { description = "An optional boolean value telling the plugin to show or hide the credential from the upstream service.", type = "boolean", required = true, default = false }, },
          { clock_skew = { description = "Clock skew in seconds to prevent replay attacks.", type = "number", default = 300, gt = 0 }, },
          { anonymous = { description = "An optional string (Consumer UUID or username) value to use as an “anonymous” consumer if authentication fails.", type = "string" }, },
          { validate_request_body = { description = "A boolean value telling the plugin to enable body validation.", type = "boolean", required = true, default = false }, },
          { enforce_headers = { description = "A list of headers that the client should at least use for HTTP signature creation.", type = "array",
              elements = { type = "string" },
              default = {},
          }, },
          { algorithms = { description = "A list of HMAC digest algorithms that the user wants to support. Allowed values are `hmac-sha1`, `hmac-sha256`, `hmac-sha384`, and `hmac-sha512`", type = "array",
              elements = { type = "string", one_of = ALGORITHMS },
              default = ALGORITHMS,
          }, },
          { realm = { description = "When authentication fails the plugin sends `WWW-Authenticate` header with `realm` attribute value.", type = "string", required = false }, },
        },
      },
    },
  },
  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config.algorithms", },
      fn = function(entity)
        local algs = entity.config.algorithms or {}
        if _G.kong and kong.configuration.fips then
          for _, alg in ipairs(algs) do
            if alg == "hmac-sha1" then
              return nil, "\"hmac-sha1\" is disabled in FIPS mode"
            end
          end
        end
        return true
      end
    } },
  },
}
