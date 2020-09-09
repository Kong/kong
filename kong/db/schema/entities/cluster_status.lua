local typedefs      = require "kong.db.schema.typedefs"

return {
  name        = "cluster_status",
  primary_key = { "id" },

  fields = {
    { id = typedefs.uuid { required = true, }, },
    { last_seen = typedefs.auto_timestamp_s },
    { ip = typedefs.ip { required = true, } },
    { config_hash = { type = "string", len_eq = 32, } },
    { hostname = typedefs.host { required = true, } },
  },
}
