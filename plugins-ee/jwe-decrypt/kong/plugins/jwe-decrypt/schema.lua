-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "jwe-decrypt",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer = typedefs.no_consumer },
    { config = {
      type = "record",
      fields = {
        { lookup_header_name = {
          type = "string",
          required = true,
          default = "Authorization"
        } },
        { forward_header_name = {
          type = "string",
          required = true,
          default = "Authorization"
        } },
        { key_sets = {
          type = "array",
          elements = { type = "string" },
          required = true
        } },
        { strict = {
            type = "boolean",
            default = true,
          }
        }
      },
    },
    }
  }
}
