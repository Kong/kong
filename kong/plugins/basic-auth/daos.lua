local typedefs = require "kong.db.schema.typedefs"


return {
  basicauth_credentials = {
    dao = "kong.plugins.basic-auth.basicauth_credentials",
    name = "basicauth_credentials",
    primary_key = { "id" },
    cache_key = { "username" },
    endpoint_key = "username",
    workspaceable = true,

    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", default = ngx.null, on_delete = "cascade", }, },
      { username = { type = "string", required = true, unique = true }, },
      { password = { type = "string", required = true }, },
    },
  },
}
