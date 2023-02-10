local Schema = require "kong.db.schema"
local typedefs = require "kong.db.schema.typedefs"


local Filter = Schema.define {
  type = "record",
  fields = {
    { name = { type = "string", required = true, --[[default = false]] }, },
    { config = { type = "string" }, },
  },
}


return {
  name = "proxy-wasm",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { filters = { type = "array", elements = Filter, required = true }},
        },
      },
    },
  }
}
