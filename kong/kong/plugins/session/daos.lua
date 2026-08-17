local typedefs = require "kong.db.schema.typedefs"


local sessions = {
  primary_key = { "id" },
  endpoint_key = "session_id",
  name = "sessions",
  cache_key = { "session_id" },
  ttl = true,
  db_export = false,
  fields = {
    { id = typedefs.uuid },
    { session_id = { type = "string", unique = true, required = true } },
    { expires = { type = "integer" } },
    { data = { type = "string" } },
    { created_at = typedefs.auto_timestamp_s },
  }
}

local session_metadatas = {
  primary_key = { "id" },
  name = "session_metadatas",
  dao  = "kong.plugins.session.daos.session_metadatas",
  generate_admin_api = false,
  db_export = false,
  fields = {
    { id = typedefs.uuid },
    { session = { type = "foreign", reference = "sessions", required = true, on_delete = "cascade" } },
    { sid = { type = "string" } },
    { audience = { type = "string" } },
    { subject = { type = "string" } },
    { created_at = typedefs.auto_timestamp_s },
  }
}

return {
  sessions,
  session_metadatas,
}
