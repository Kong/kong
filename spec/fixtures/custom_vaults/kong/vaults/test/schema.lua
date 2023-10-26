-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local typedefs = require "kong.db.schema.typedefs"


return {
  name = "test",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { default_value     = { type = "string", required = false } },
          { default_value_ttl = { type = "number", required = false } },
          { ttl                 = typedefs.ttl },
          { neg_ttl             = typedefs.ttl },
          { resurrect_ttl       = typedefs.ttl },
        },
      },
    },
  },
}
