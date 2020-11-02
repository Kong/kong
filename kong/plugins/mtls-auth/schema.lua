-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Copyright 2019 Kong Inc.


local typedefs = require("kong.db.schema.typedefs")


return {
  name = "mtls-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { anonymous = { type = "string", uuid = true, legacy = true }, },
          { consumer_by = {
            type = "array",
            elements = { type = "string", one_of = { "username", "custom_id" }},
            required = false,
            default = { "username", "custom_id" },
          }, },
          { ca_certificates = {
            type = "array",
            required = true,
            elements = { type = "string", uuid = true, },
          }, },
          { cache_ttl = {
            type = "number",
            required = true,
            default = 60
          }, },
          { skip_consumer_lookup = {
            type = "boolean",
            required = true,
            default = false
          }, },
          { authenticated_group_by = {
            required = false,
            type = "string",
            one_of = {"CN", "DN"},
            default = "CN"
          }, },
          { revocation_check_mode = {
            required = false,
            type = "string",
            one_of = {"SKIP", "IGNORE_CA_ERROR", "STRICT"},
            default = "IGNORE_CA_ERROR"
          }, },
          { http_timeout = {
            type = "number",
            default = 30000,
          }, },
          { cert_cache_ttl = {
            type = "number",
            default = 60000,
          }, },
        },
    }, },
  },
}
