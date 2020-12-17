local typedefs      = require "kong.db.schema.typedefs"
local CLUSTERING_SYNC_STATUS = require "kong.constants".CLUSTERING_SYNC_STATUS
local SYNC_STATUS_CHOICES = {}


for _, v in ipairs(CLUSTERING_SYNC_STATUS) do
  _, v = next(v)
  table.insert(SYNC_STATUS_CHOICES, v)
end


return {
  name               = "clustering_data_planes",
  primary_key        = { "id" },
  db_export          = false,
  generate_admin_api = false,
  admin_api_name     = "clustering/data-planes", -- we don't generate this, so just for reference
  ttl                = true,

  fields = {
    { id = typedefs.uuid { required = true, }, },
    { last_seen = typedefs.auto_timestamp_s },
    { ip = typedefs.ip { required = true, } },
    { config_hash = { type = "string", len_eq = 32, } },
    { hostname = typedefs.host { required = true, } },
    { version = typedefs.semantic_version },
    { sync_status = { type = "string",
                      required = true,
                      one_of = SYNC_STATUS_CHOICES,
                      default = "unknown",
                    }
    },
  },
}
