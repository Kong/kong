local workspaces = require "kong.workspaces"
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_role_endpoints",
  primary_key = { "role_id", "workspace", "endpoint" },
  fields = {
    { role_id = {type = "id", required = true, immutable = true,} },
    { workspace = {type = "string", required = true, default = workspaces.DEFAULT_WORKSPACE, immutable = true}},
    { endpoint = {type = "string", required = true, immutable = true,} },
    { actions = {type = "number", required = true,} },
    { negative = {type = "boolean", required = true, default = false,}},
    { comment = {type = "string",} },
    { created_at     = typedefs.auto_timestamp_s },
  },
}
