local typedefs = require "kong.db.schema.typedefs"

return {
  {
    ttl = true,
    primary_key = { "id" },
    cache_key = { "key" },
    name = "acme_storage",
    fields = {
      { id = typedefs.uuid },
      { key = { type = "string", required = true, unique = true, auto = true }, },
      { value = { type = "string", required = true, auto = true }, },
      { created_at = typedefs.auto_timestamp_s },
    },
  },
}
