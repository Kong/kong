-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


local ALGORITHMS = {
  "hmac-sha1",
  "hmac-sha256",
  "hmac-sha384",
  "hmac-sha512",
}


return {
  name = "hmac-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { hide_credentials = { type = "boolean", default = false }, },
          { clock_skew = { type = "number", default = 300, gt = 0 }, },
          { anonymous = { type = "string" }, },
          { validate_request_body = { type = "boolean", default = false }, },
          { enforce_headers = {
              type = "array",
              elements = { type = "string" },
              default = {},
          }, },
          { algorithms = {
              type = "array",
              elements = { type = "string", one_of = ALGORITHMS },
              default = ALGORITHMS,
          }, },
        },
      },
    },
  },
}
