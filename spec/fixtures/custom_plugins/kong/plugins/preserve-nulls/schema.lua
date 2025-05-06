local typedefs = require "kong.db.schema.typedefs"


local PLUGIN_NAME = "PreserveNulls"

local schema = {
  name = PLUGIN_NAME,
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { request_header = typedefs.header_name {
              required = true,
              default = "Hello-World" } },
          { response_header = typedefs.header_name {
              required = true,
              default = "Bye-World" } },
          { large = {
              type = "integer",
              default = 100 } },
          { ttl = {
            type = "integer" } },
        },
      },
    },
  },
}

return schema
