local typedefs = require "kong.db.schema.typedefs"

return {
  degraphql_routes = {
    name = "degraphql_routes",
    primary_key = { "id" },
    endpoint_key = "id",
    -- cache_key = { "service", "method", "uri" },
    fields = {
      { id = typedefs.uuid },
      { service = { type = "foreign", reference = "services" } },
      { methods = { type = "set", elements = typedefs.http_method,
                    default = { "GET" } } },
      { uri = { type = "string", required = true } },
      { query = { type = "string", required = true } },
      { created_at = typedefs.auto_timestamp_s },
      { updated_at = typedefs.auto_timestamp_s },
    }
  },
}
