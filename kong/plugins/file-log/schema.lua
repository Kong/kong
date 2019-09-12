local typedefs = require "kong.db.schema.typedefs"

return {
  name = "file-log",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { path = { type = "string",
                     required = true,
                     match = [[^[^*&%%\`]+$]],
                     err = "not a valid filename",
          }, },
          { reopen = { type = "boolean", default = false }, },
    }, }, },
  }
}
