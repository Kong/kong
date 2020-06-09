local typedefs = require "kong.db.schema.typedefs"
local null = ngx.null

return {
  name = "application-registration",
  fields = {
    { consumer = typedefs.no_consumer },
    { service = { type = "foreign", reference = "services", ne = null, on_delete = "cascade" }, },
    { route = typedefs.no_route },
    { run_on = typedefs.run_on_first },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { display_name = { type = "string", unique = true, required = true }, },
          { description = { type = "string", unique = true }, },
          { auto_approve = { type = "boolean", required = true, default = false }, },
          { show_issuer = { type = "boolean", required = true, default = false }, },
        },
      },
    },
  },
}
