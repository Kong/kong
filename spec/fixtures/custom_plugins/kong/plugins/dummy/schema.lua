-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "dummy",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { resp_header_value = { type = "string", default = "1", referenceable = true } },
          { resp_headers = {
            type   = "map",
            keys   = typedefs.header_name,
            values = {
              type          = "string",
              referenceable = true,
            }
          }},
          { append_body = { type = "string" } },
          { resp_code = { type = "number" } },
          { test_try = { type = "boolean", default = false}}
        },
      },
    },
  },
}
