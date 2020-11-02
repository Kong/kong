-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local strategies = require "kong.plugins.graphql-proxy-cache-advanced.strategies"

return {
  name = "graphql-proxy-cache-advanced",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { strategy = {
            type = "string",
            one_of = strategies.STRATEGY_TYPES,
            default = "memory",
            required = true,
          } },
          { cache_ttl = {
            type = "integer",
            default = 300,
            gt = 0,
          } },
          { memory = {
            type = "record",
            fields = {
              { dictionary_name = {
                type = "string",
                required = true,
                default = "kong_db_cache",
              } },
            },
          } },
          { vary_headers = {
            type = "array",
            elements = { type = "string" },
          }},
        }
      }
    }
  }
}
