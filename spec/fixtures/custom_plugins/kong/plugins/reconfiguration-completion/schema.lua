local typedefs = require "kong.db.schema.typedefs"

return {
  name   = "reconfiguration-completion",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
      type   = "record",
      fields = {
        { version = { description = "Client-assigned version number for the current Kong Gateway configuration",
                      type = "string",
                      required = true, } },
      },
    }, },
  }
}
