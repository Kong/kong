local typedefs = require "kong.db.schema.typedefs"


return {
  name = "request-size-limiting",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allowed_payload_size = { type = "integer", default = 128 }, },
        },
      },
    },
  },
}
