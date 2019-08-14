local typedefs = require "kong.db.schema.typedefs"

return {
  service_maps = {
    name = "service_maps",
    primary_key = { "workspace_id" },
    generate_admin_api = false,
    fields = {
      { workspace_id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { service_map = { type = "string", required = true } },
    },
  },
}
