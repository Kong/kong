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
