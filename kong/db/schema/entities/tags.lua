local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "tags",
  primary_key  = { "tag" },
  endpoint_key = "tag",
  dao          = "kong.db.dao.tags",
  db_export = false,

  fields = {
    { tag          = typedefs.tag, },
    { entity_name  = { type = "string", required = true, unique = false }, },
    { entity_id    = { type = "string",
                        elements = typedefs.uuid,
                        unique = true,
                        required = true }, },
    }

}
