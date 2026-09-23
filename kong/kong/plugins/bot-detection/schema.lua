local typedefs = require "kong.db.schema.typedefs"

return {
  name = "bot-detection",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allow = { description = "An array of regular expressions that should be allowed. The regular expressions will be checked against the `User-Agent` header.", type = "array",
              elements = { type = "string", is_regex = true },
              default = {},
          }, },
          { deny = { description = "An array of regular expressions that should be denied. The regular expressions will be checked against the `User-Agent` header.", type = "array",
              elements = { type = "string", is_regex = true },
              default = {},
          }, },
        },
    }, },
  },
}
