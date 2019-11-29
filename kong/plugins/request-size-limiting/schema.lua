local typedefs = require "kong.db.schema.typedefs"
local handler = require "kong.plugins.request-size-limiting.handler"


local size_units = handler.size_units


return {
  name = "request-size-limiting",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allowed_payload_size = { type = "integer", default = 128 }, },
          { size_unit = { type = "string", required = true, default = size_units[1], one_of = size_units }, },
        },
      },
    },
  },
}
