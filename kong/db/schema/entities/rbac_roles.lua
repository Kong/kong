local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_roles",
  endpoint_key = "name",
  primary_key = { "id" },
  dao = "kong.db.dao.rbac_roles",
  workspaceable = true,
  fields = {
    { id             = typedefs.uuid, },
    { name           =  {type = "string", required = true, unique = true}}, -- we accept '@' so it's not a typedef.name
    { comment = {type = "string"} },
    { created_at     = typedefs.auto_timestamp_s },
    { is_default = {type = "boolean", required = true, default = false} },
  }
}
