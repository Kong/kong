local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_roles",
  generate_admin_api = false,
  admin_api_name = "/rbac/roles",
  endpoint_key = "name",
  primary_key = { "id" },
  workspaceable = true,
  fields = {
    { id             = typedefs.uuid, },
    { name           =  {type = "string", required = true, unique = true}}, -- we accept '@' so it's not a typedef.name
    { comment = {type = "string"} },
    { created_at     = typedefs.auto_timestamp_s },
    { is_default = {type = "boolean", required = true, default = false} },
  }
}
