-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  vaults = {
    primary_key = { "id" },
    name = "vaults",
    endpoint_key = "name",
  
    fields = {
      { id            = typedefs.uuid, },
      { created_at    = typedefs.auto_timestamp_s, },
      { updated_at    = typedefs.auto_timestamp_s, },
      { name          = typedefs.name, },
      { protocol      = { type    = "string",
                          one_of  = { "http", "https" },
                          default = "http",
                        }, },
      { host          = typedefs.host { required = true } },
      { port          = typedefs.port { required = true, default = 8200, }, },
      { mount         = { type = "string", required = true, }, },
      { vault_token   = { type = "string", required = true, }, },
    },
  }
}
