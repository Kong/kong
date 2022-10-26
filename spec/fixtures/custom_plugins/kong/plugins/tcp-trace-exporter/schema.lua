local typedefs = require "kong.db.schema.typedefs"

return {
  name = "tcp-trace-exporter",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { host = typedefs.host({ required = true }), },
          { port = typedefs.port({ required = true }), },
          { custom_spans = { type = "boolean", default = false }, }
        }
      }
    }
  }
}
