local typedefs = require "kong.db.schema.typedefs"
local ee_typedefs = require "kong.enterprise_edition.db.typedefs"

return {
  name         = "admins",
  primary_key  = { "id" },
  endpoint_key = "username",
  dao          = "kong.db.dao.admins",

  fields = {
    { id             = typedefs.uuid },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { username       = { type = "string",  unique = true }, },
    { custom_id      = { type = "string",  unique = true }, },
    { email          = ee_typedefs.email { unique = true } },
    { status         = ee_typedefs.admin_status { required = true } },
    { consumer       = { type = "foreign", reference = "consumers", required = true } },
    { rbac_user      = { type = "foreign", reference = "rbac_users", required = true } },
  },

  entity_checks = {
    { at_least_one_of = { "custom_id", "username" } },
  },
}
