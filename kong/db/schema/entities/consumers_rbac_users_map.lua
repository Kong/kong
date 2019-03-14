local typedefs = require "kong.db.schema.typedefs"

return {
  name = "consumers_rbac_users_map",
  primary_key = { "consumer_id", "user_id" },
  -- cache_key = { "user_id" },
  fields = {
    {consumer_id      = { type = "string",  unique = true }, },
    {user_id      = { type = "string",  unique = true }, },
    { created_at = typedefs.auto_timestamp_s },
  },
}
