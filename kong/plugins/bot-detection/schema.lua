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
        shorthand_fields = {
          -- deprecated forms, to be removed in Kong 3.0
          { blacklist = {
              type = "array",
              elements = { type = "string", is_regex = true },
              func = function(value)
                return { deny = value }
              end,
          }, },
          { whitelist = {
              type = "array",
              elements = { type = "string", is_regex = true },
              func = function(value)
                return { allow = value }
              end,
          }, },
        },
    }, },
  },
}
