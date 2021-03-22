local typedefs = require "kong.db.schema.typedefs"

return {
  name = "udp-log",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { host = typedefs.host({ required = true }) },
          { port = typedefs.port({ required = true }) },
          { timeout = { type = "number", default = 10000 }, },
          { custom_fields_by_lua = typedefs.lua_code },
    }, }, },
  },
}
