local typedefs = require "kong.db.schema.typedefs"

return {
  keyauth_credentials = {
    primary_key = { "id" },
    name = "keyauth_credentials",
    endpoint_key = "key",
    cache_key = { "key" },
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { kongsumer = { type = "foreign", reference = "kongsumers", default = ngx.null, on_delete = "cascade", }, },
      { key = { type = "string", required = false, unique = true, auto = true }, },
    },
  },
}

