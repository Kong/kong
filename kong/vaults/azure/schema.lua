-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local typedefs = require "kong.db.schema.typedefs"


return {
  name = "azure",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { vault_uri = typedefs.url { required = true } },
          { credentials_prefix = { type = "string", required = true, default = "AZURE", }, },
          { type = { type = "string", required = true, one_of = { "secrets", }, default = "secrets", }, },
          { tenant_id = { type = "string", }, },
          { client_id = { type = "string", }, },
          { location = { type = "string", required = true, }, },
          { ttl = typedefs.ttl },
          { neg_ttl = typedefs.ttl },
          { resurrect_ttl = typedefs.ttl },
        },
      },
    },
  },
}
