local typedefs = require "kong.db.schema.typedefs"

return {
  name = "bot-detection",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allow = {
              type = "array",
              elements = { type = "string", is_regex = true },
              default = {},
          }, },
          { deny = {
              type = "array",
              elements = { type = "string", is_regex = true },
              default = {},
          }, },
        },
    }, },
  },
}
