local typedefs = require "kong.db.schema.typedefs"


return {
  name = "targets",
  dao = "kong.db.dao.targets",
  primary_key = { "id" },
  endpoint_key = "target",
  workspaceable = true,
  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_ms },
    { upstream   = { type = "foreign", reference = "upstreams", required = true, on_delete = "cascade" }, },
    { target     = typedefs.proxy_target { required = true }, },
    { weight     = { type = "integer", default = 100, between = { 0, 65535 }, }, },
    { tags       = typedefs.tags },
  },
}
