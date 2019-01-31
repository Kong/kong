local typedefs = require "kong.db.schema.typedefs"

return {
  keyauth_credentials = {
    primary_key = { "id" },
    name = "keyauth_credentials",
    endpoint_key = "key",
    cache_key = { "key" },
    workspaceable = true,
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", default = ngx.null, on_delete = "cascade", }, },
      { key = { type = "string", required = false, unique = true, auto = true }, },
    },
  },
}

