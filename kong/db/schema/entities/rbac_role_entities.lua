local typedefs = require "kong.db.schema.typedefs"

return {
  name = "rbac_role_entities",
  primary_key = { "role_id", "entity_id" },
  fields = {
    { role_id = {type = "id", required = true, immutable = true,} },
    { entity_id = {type = "string", required = true,} },
    { entity_type = {type = "string", required = true, immutable = true,} },
    { actions = {type = "number", required = true,} },
    { negative = {type = "boolean", required = true, default = false,} },
    { comment = {type = "string",} },
    { created_at     = typedefs.auto_timestamp_s },
  },
}
