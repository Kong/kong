local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "consumers",
  primary_key  = { "id" },
  endpoint_key = "username",

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { username       = { type = "string",  unique = true }, },
    { custom_id      = { type = "string",  unique = true }, },
    { tags           = typedefs.tags },
  },

  entity_checks = {
    { at_least_one_of = { "custom_id", "username" } },
  },
}
