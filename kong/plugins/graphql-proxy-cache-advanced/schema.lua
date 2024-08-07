-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local strategies = require "kong.plugins.graphql-proxy-cache-advanced.strategies"
local redis      = require "kong.enterprise_edition.tools.redis.v2"
local typedefs = require "kong.db.schema.typedefs"


return {
  name = "graphql-proxy-cache-advanced",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    {
      config = {
        type = "record",
        fields = {
          { strategy = { description = "The backing data store in which to hold cached entities. Accepted value is `memory`.",
            type = "string",
            one_of = strategies.STRATEGY_TYPES,
            default = "memory",
            required = true,
          } },
          { cache_ttl = { description = "TTL in seconds of cache entities. Must be a value greater than 0.",
            type = "integer",
            default = 300,
            gt = 0,
          } },
          { memory = {
            type = "record",
            fields = {
              { dictionary_name = { description = "The name of the shared dictionary in which to hold cache entities when the memory strategy is selected. This dictionary currently must be defined manually in the Kong Nginx template.", type = "string",
                required = true,
                default = "kong_db_cache",
              } },
            },
          } },
          { redis = redis.config_schema },
          { bypass_on_err = { description = "Unhandled errors while trying to retrieve a cache entry (such as redis down) are resolved with `Bypass`, with the request going upstream.", type = "boolean",
            default = false,
          }},
          { vary_headers = { description = "Relevant headers considered for the cache key. If undefined, none of the headers are taken into consideration.", type = "array",
            elements = { type = "string" },
          }},
        }
      }
    }
  }
}
