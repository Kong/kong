local typedefs = require "kong.db.schema.typedefs"

return {
  name = "bot-detection",
  fields = {
    { kongsumer = typedefs.no_kongsumer },
    { run_on = typedefs.run_on_first },
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
