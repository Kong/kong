local typedefs = require "kong.db.schema.typedefs"
local ee_typedefs = require "kong.enterprise_edition.db.typedefs"

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
    { type           = ee_typedefs.consumer_type { required = true } },
  },

  entity_checks = {
    { at_least_one_of = { "custom_id", "username" } },
  },
}
