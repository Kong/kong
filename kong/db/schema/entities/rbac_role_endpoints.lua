local workspaces = require "kong.workspaces"
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_role_endpoints",
  generate_admin_api = false,
  primary_key = { "role_id", "workspace", "endpoint" },
  fields = {
    { role_id = typedefs.uuid},
    { workspace = {type = "string", required = true, default = workspaces.DEFAULT_WORKSPACE}},
    { endpoint = {type = "string", required = true} },
    { actions = {type = "number", required = true,} },
    { negative = {type = "boolean", required = true, default = false,}},
    { comment = {type = "string",} },
    { created_at     = typedefs.auto_timestamp_s },
  },
}
