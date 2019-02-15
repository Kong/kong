local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_roles",
  workspaceable = true,
  primary_key = { "id" },
  fields = {
    { id             = typedefs.uuid, },
    { name           = typedefs.name },
    { comment = {type = "string"} },
    { created_at     = typedefs.auto_timestamp_s },
    { is_default = {type = "boolean", required = true, default = false} },
  }
}
