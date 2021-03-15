local typedefs = require "kong.db.schema.typedefs"


return {
  name = "key-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { key_names = {
              type = "array",
              required = true,
              elements = typedefs.header_name,
              default = { "apikey" },
          }, },
          { hide_credentials = { type = "boolean", required = true, default = false }, },
          { anonymous = { type = "string" }, },
          { key_in_header = { type = "boolean", required = true, default = true }, },
          { key_in_query = { type = "boolean", required = true, default = true }, },
          { key_in_body = { type = "boolean", required = true, default = false }, },
          { run_on_preflight = { type = "boolean", required = true, default = true }, },
        },
    }, },
  },
}
