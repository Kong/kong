local typedefs = require "kong.db.schema.typedefs"

return {
  name         = "consumers",
  primary_key  = { "id" },
  endpoint_key = "username",
  dao          = "kong.db.dao.consumers",

  fields = {
    { id             = typedefs.uuid, },
    { created_at     = { type = "integer", timestamp = true, auto = true }, },
    { username       = { type = "string",  unique = true }, },
    { custom_id      = { type = "string",  unique = true }, },
  },

  entity_checks = {
    { at_least_one_of = { "custom_id", "username" } },
  },
}
