local typedefs = require "kong.db.schema.typedefs"
return {
  name = "rbac_users",
  primary_key = { "id" },
  endpoint_key = "name",
  cache_key = { "name" },
  workspaceable = true,
    fields = {
    { id             = typedefs.uuid, },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { name           = typedefs.name },
    { user_token     = {type = "string", required = true, unique = true}},
    { user_token_ident = {type = "string"}},
    { comment = {type "string"} },
    { enabled = {type = "boolean", required = true, default = true}}
    }
}
