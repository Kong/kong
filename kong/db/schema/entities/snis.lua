local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "snis",
  primary_key  = { "id" },
  endpoint_key = "name",
  dao          = "kong.db.dao.snis",

  fields = {
    { id           = typedefs.uuid, },
    { name         = { type = "string", required = true, unique = true }, },
    { created_at   = { type = "integer", timestamp = true, auto = true }, },
    { certificate  = { type = "foreign", reference = "certificates", required = true }, },
  },

}
