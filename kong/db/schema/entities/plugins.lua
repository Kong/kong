local typedefs = require "kong.db.schema.typedefs"
local null = ngx.null


return {
  name = "plugins",
  primary_key = { "id" },
  cache_key = { "name", "route", "service", "consumer" },
  dao = "kong.db.dao.plugins",
  workspaceable = true,
  endpoint_key = "instance_name",

  subschema_key = "name",
  subschema_error = "plugin '%s' not enabled; add it to the 'plugins' configuration property",

  fields = {
    { id = typedefs.uuid, },
    { name = { description = "The name of the Plugin that's going to be added.", type = "string", required = true, }, },
    { instance_name = typedefs.utf8_name },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { route = { description = "If set, the plugin will only activate when receiving requests via the specified route.", type = "foreign", reference = "routes", default = null, on_delete = "cascade", }, },
    { service = { description = "If set, the plugin will only activate when receiving requests via one of the routes belonging to the specified service. ", type = "foreign", reference = "services", default = null, on_delete = "cascade", }, },
    { consumer = { description = "If set, the plugin will activate only for requests where the specified has been authenticated.", type = "foreign", reference = "consumers", default = null, on_delete = "cascade", }, },
    { config = { description = "The configuration properties for the Plugin.", type = "record", abstract = true, }, },
    { protocols = typedefs.protocols },
    { enabled = { description = "Whether the plugin is applied.", type = "boolean", required = true, default = true }, },
    { tags           = typedefs.tags },
  },
}
