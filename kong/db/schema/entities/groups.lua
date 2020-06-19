local typedefs = require "kong.db.schema.typedefs"

return {
  name               = "groups",
  generate_admin_api = false,
  primary_key        = { "id" },
  cache_key          = { "name" },
  endpoint_key       = "name",
  admin_api_name = "groups",
  workspaceable      = false,

  fields = {
    { id             = typedefs.uuid },
    { created_at     = typedefs.auto_timestamp_s },
    { name           = { type = "string", required = true, unique = true }},
    { comment        = { type = "string" }},
  },
}
