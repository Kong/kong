local typedefs = require "kong.db.schema.typedefs"


return {
  name = "workspace_entity_counters",
  primary_key = { "workspace_id", "entity_type"},

  fields = {
    { workspace_id = typedefs.uuid },
    { entity_type = { type = "string", required = true } },
    { count = { type = "integer" } },
  }
}
