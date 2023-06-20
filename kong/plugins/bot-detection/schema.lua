-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "bot-detection",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allow = { description = "An array of regular expressions that should be allowed. The regular expressions will be checked against the `User-Agent` header.", type = "array",
              elements = { type = "string", is_regex = true },
              default = {},
          }, },
          { deny = { description = "An array of regular expressions that should be denied. The regular expressions will be checked against the `User-Agent` header.", type = "array",
              elements = { type = "string", is_regex = true },
              default = {},
          }, },
        },
    }, },
  },
}
