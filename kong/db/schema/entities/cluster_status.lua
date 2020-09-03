local typedefs      = require "kong.db.schema.typedefs"
local ngx_time      = ngx.time

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

  transformations = {
    {
      input = { "last_seen" },
      on_read = function(last_seen)
        if ngx_time() - last_seen > 60 then
          return { status = "disconnected", }
        end

        return { status = "connected", }
      end,
    },
  },
}
