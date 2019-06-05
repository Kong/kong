local typedefs = require "kong.db.schema.typedefs"

return {
  name = "udp-log",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { host = typedefs.host({ required = true }) },
          { port = typedefs.port({ required = true }) },
          { timeout = { type = "number", default = 10000 }, },
    }, }, },
  },
}
