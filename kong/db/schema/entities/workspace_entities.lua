local typedefs = require "kong.db.schema.typedefs"


return {
  name = "workspace_entities",
  primary_key = { "workspace_id", "entity_id", "unique_field_name" },
  generate_admin_api = false,

  fields = {
    { workspace_id = typedefs.uuid },
    { workspace_name = { type = "string", required = true } },
    { entity_id = { type = "string", required = true } }, -- XXX explain why entity_id is not a uuid
    { entity_type = { type = "string" } },
    { unique_field_name = { type = "string", required = true } },
    { unique_field_value = { type = "string" } },
  }
}
