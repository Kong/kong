local typedefs = require "kong.db.schema.typedefs"
local null = ngx.null


return {
  name = "plugins",
  primary_key = { "id" },
  cache_key = { "name", "route", "service", "consumer" },
  dao = "kong.db.dao.plugins",

  subschema_key = "name",
  subschema_error = "plugin '%s' not enabled; add it to the 'plugins' configuration property",

  fields = {
    { id = typedefs.uuid, },
    { name = { type = "string", required = true, }, },
    { created_at = typedefs.auto_timestamp_s },
    { route = { type = "foreign", reference = "routes", default = null, on_delete = "cascade", }, },
    { service = { type = "foreign", reference = "services", default = null, on_delete = "cascade", }, },
    { consumer = { type = "foreign", reference = "consumers", default = null, on_delete = "cascade", }, },
    { config = { type = "record", abstract = true, }, },
    { protocols = typedefs.protocols },
    { enabled = { type = "boolean", default = true, }, },
    { tags           = typedefs.tags },
  },
}
