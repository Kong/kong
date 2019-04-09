local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_role_entities",
  generate_admin_api = false,
  primary_key = { "role", "entity_id" },
  fields = {
    { role = { type = "foreign", required = true, reference = "rbac_roles", on_delete = "cascade" } }, -- XXX EE
    { entity_id = {type = "string", required = true,} },
    { entity_type = {type = "string", required = true} },
    { actions = {type = "integer", required = true,} },
    { negative = {type = "boolean", required = true, default = false,} },
    { comment = {type = "string",} },
    { created_at  = typedefs.auto_timestamp_s },
  },
}
