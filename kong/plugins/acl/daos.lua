local typedefs = require "kong.db.schema.typedefs"

return {
  acls = {
    dao = "kong.plugins.acl.acls",
    name = "acls",
    primary_key = { "id" },
    endpoint_key = "group",
    cache_key = { "kongsumer", "group" },
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { kongsumer = { type = "foreign", reference = "kongsumers", default = ngx.null, on_delete = "cascade", }, },
      { group = { type = "string", required = true } },
    },
  },
}
