local typedefs = require "kong.db.schema.typedefs"

return {
  name        = "certificates",
  primary_key = { "id" },
  dao         = "kong.db.dao.certificates",

  fields = {
    { id = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp },
    { cert           = { type = "string",  required = true}, },
    { key            = { type = "string",  required = true}, },
  },

}
