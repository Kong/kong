local typedefs = require "kong.db.schema.typedefs"


return {
  name = "request-size-limiting",
  fields = {
    { run_on = typedefs.run_on_first },
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
