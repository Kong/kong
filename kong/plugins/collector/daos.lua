local typedefs = require "kong.db.schema.typedefs"

return {
  service_maps = {
    name = "service_maps",
    primary_key = { "id" },
    generate_admin_api = false,
    fields = {
      { id = { type = "string", unique = true, reference = "workspaces" } },
      { created_at = typedefs.auto_timestamp_s },
      { service_map = { type = "string", required = true } },
    },
  },
}
