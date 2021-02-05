local typedefs = require "kong.db.schema.typedefs"

local schema = {
  name = "opa",
  fields = {
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
            opa_port = typedefs.port{ required =true, default = 80 },
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

