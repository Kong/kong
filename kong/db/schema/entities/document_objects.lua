local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "document_objects",
  endpoint_key  = "path",
  primary_key  = { "id" },
  workspaceable = true,
  -- dao           = "kong.db.dao.document_objects",

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { service        = { type = "foreign", reference = "services" }, },
    { path           = { type = "string", required = true , unique = true}, },
  },
}
