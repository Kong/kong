local typedefs = require "kong.db.schema.typedefs"


return {
  hmacauth_credentials = {
    primary_key = { "id" },
    name = "hmacauth_credentials",
    endpoint_key = "username",
    cache_key = { "username" },
    workspaceable = true,

    admin_api_name = "hmac-auths",
    admin_api_nested_name = "hmac-auth",
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", default = ngx.null, on_delete = "cascade", }, },
      { username = { type = "string", required = true, unique = true }, },
      { secret = { type = "string", auto = true }, },
    },
  },
}
