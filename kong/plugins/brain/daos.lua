local typedefs = require "kong.db.schema.typedefs"

return {
  brain_service_maps = {
    name = "brain_service_maps",
    primary_key = { "id" },
    endpoint_key = "singleton",
    generate_admin_api = true,
    fields = {
      { id = typedefs.uuid },
      { singleton = { type = "string", default = "singleton", eq = "singleton", } },
      { created_at = typedefs.auto_timestamp_s },
      { service_map = { type = "string", required = true } },
    },
  },
}
