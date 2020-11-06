-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "correlation-id",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { header_name = { type = "string", default = "Kong-Request-ID" }, },
          { generator = { type = "string", default = "uuid#counter",
                          one_of = { "uuid", "uuid#counter", "tracker" }, }, },
          { echo_downstream = { type = "boolean", default = false, }, },
        },
      },
    },
  },
}
