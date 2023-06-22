-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "grpc-web",
  fields = {
    { protocols = typedefs.protocols },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
      type = "record",
      fields = {
        {
          proto = { description = "If present, describes the gRPC types and methods. Required to support payload transcoding. When absent, the web client must use application/grpw-web+proto content.", type = "string",
            required = false,
            default = nil,
          },
        },
        {
          pass_stripped_path = { description = "If set to `true` causes the plugin to pass the stripped request path to the upstream gRPC service.", type = "boolean",
            required = false,
          },
        },
        {
          allow_origin_header = { description = "The value of the `Access-Control-Allow-Origin` header in the response to the gRPC-Web client.", type = "string",
            required = false,
            default = "*",
          },
        },
      },
    }, },
  },
}
