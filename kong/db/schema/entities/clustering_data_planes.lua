-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
    { updated_at = typedefs.auto_timestamp_s },
    { ip = typedefs.ip { required = true, } },
    { config_hash = { description = "The hash of the data plane's configuration.", type = "string", len_eq = 32, } },
    { hostname = typedefs.host { required = true, } },
    { version = typedefs.semantic_version },
    { sync_status = { description = "The status of the clustering data plane's synchronization.",
                      type = "string",
                      required = true,
                      one_of = SYNC_STATUS_CHOICES,
                      default = "unknown",
                    }
    },
    { labels = { type = "map",
                 keys = { type = "string" },
                 values = { type = "string" },
                 description = "Custom key value pairs as meta-data for DPs.",
               },
    },
  },
}
