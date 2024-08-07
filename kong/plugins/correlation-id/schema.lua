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
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { header_name = { description = "The HTTP header name to use for the correlation ID.", type = "string", default = "Kong-Request-ID" }, },
          { generator = { description = "The generator to use for the correlation ID. Accepted values are `uuid`, `uuid#counter`, and `tracker`. See [Generators](#generators).",
                          type = "string", default = "uuid#counter", required = true, one_of = { "uuid", "uuid#counter", "tracker" }, }, },
          { echo_downstream = { description = "Whether to echo the header back to downstream (the client).", type = "boolean", required = true, default = false, }, },
        },
      },
    },
  },
}
