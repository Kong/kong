local typedefs = require "kong.db.schema.typedefs"


return {
  name = "basic-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { anonymous = { type = "string" }, },
          { hide_credentials = { type = "boolean", default = false }, },
    }, }, },
  },
}
