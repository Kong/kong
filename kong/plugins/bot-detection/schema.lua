local typedefs = require "kong.db.schema.typedefs"

return {
  name = "bot-detection",
  fields = {
    { consumer = typedefs.no_consumer },
    { config = {
        type = "record",
        fields = {
          { whitelist = {
              type = "array",
              elements = { type = "string", is_regex = true },
              default = {},
          }, },
          { blacklist = {
              type = "array",
              elements = { type = "string", is_regex = true },
              default = {},
          }, },
    }, }, },
  },
}
