local typedefs = require "kong.db.schema.typedefs"


return {
  name = "error-generator",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { certificate   = { type = "boolean", required = false, default = false }, },
          { rewrite       = { type = "boolean", required = false, default = false }, },
          { preread       = { type = "boolean", required = false, default = false }, },
          { access        = { type = "boolean", required = false, default = false }, },
          { header_filter = { type = "boolean", required = false, default = false }, },
          { body_filter   = { type = "boolean", required = false, default = false }, },
          { log           = { type = "boolean", required = false, default = false }, },
        },
      }
    }
  }
}
