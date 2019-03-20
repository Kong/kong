local typedefs = require "kong.db.schema.typedefs"

return {
  sessions = {
    primary_key = { "id" },
    name = "sessions",
    cache_key = { "session_id" },
    ttl = true,
    fields = {
      { id = typedefs.uuid },
      { session_id = { type = "string", unique = true, required = true } },
      { expires = { type = "integer" } },
      { data = { type = "string" } },
      { created_at = typedefs.auto_timestamp_s },
    }
  }
}
