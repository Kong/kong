local typedefs = require "kong.db.schema.typedefs"


return {
  name          = "applications",
  primary_key   = { "id" },
  workspaceable = true,
  dao           = "kong.db.dao.applications",

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { redirect_uri   = typedefs.url },
    { custom_id      = { type = "string", unique = true }, },
    { name           = { type = "string", required = true }, },
    { description    = { type = "string" }, },
    { consumer       = { type = "foreign", reference = "consumers", required = true }, },
    { developer      = { type = "foreign", reference = "developers", required = true }, },
    { meta           = { type = "string" }, },
  },
}

