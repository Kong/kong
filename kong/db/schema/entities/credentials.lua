local typedefs = require "kong.db.schema.typedefs"
local ee_typedefs = require "kong.enterprise_edition.db.typedefs"

return {
  name         = "credentials",
  primary_key  = { "id" },

  fields = {
    { id              = typedefs.uuid },
    { consumer        = { type = "foreign", reference = "consumers", }, },
    { consumer_type   = ee_typedefs.consumer_type { required = true }},
    { plugin          = { type = "string", required = true }, },
    { credential_data = { type = "string", } },
    { created_at      = typedefs.auto_timestamp_s },
  },
}
