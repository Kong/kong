local typedefs = require "kong.db.schema.typedefs"

return {
  {
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
}
