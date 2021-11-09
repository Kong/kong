-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

local schema = {
  name = "opa",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          {
            opa_protocol = { type = "string", default = "http", one_of = { "http", "https" }, },
          },
          {
            opa_host = typedefs.host{ required = true, default = "localhost" },
          },
          {
            opa_port = typedefs.port{ required =true, default = 8181 },
          },
          {
            opa_path =  typedefs.path{ required = true },
          },
          {
            include_service_in_opa_input = { type = "boolean", default = false },
          },
          {
            include_route_in_opa_input = { type = "boolean", default = false },
          },
          {
            include_consumer_in_opa_input = { type = "boolean", default = false },
          },
        },
      },
    },
  },
}

return schema

