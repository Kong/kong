local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "consumers",
  primary_key  = { "id" },
  endpoint_key = "username",
  workspaceable = true,

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { username       = { type = "string",  unique = true }, },
    { custom_id      = { type = "string",  unique = true }, },
    { type           = { type = "integer", default = 0   }, },
    { email  = { type = "string" } },
    { status = { type = "integer" } },
  },

  entity_checks = {
    { at_least_one_of = { "custom_id", "username" } },
  },
}
