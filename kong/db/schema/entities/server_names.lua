local typedefs = require "kong.db.schema.typedefs"

return {
  name        = "server_names",
  primary_key = { "id" },
  dao         = "kong.db.dao.server_names",

  fields = {
    { id           = typedefs.uuid, },
    { name         = { type = "string", required = true, unique = true }, },
    { created_at   = { type = "integer", timestamp = true, auto = true }, },
    { certificate  = { type = "foreign", reference = "certificates", required = true }, },
  },

}
