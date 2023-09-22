-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis  = require "kong.enterprise_edition.redis"
local typedefs = require "kong.db.schema.typedefs"


local ngx = ngx
local concat = table.concat

local function check_shdict(name)
  if not ngx.shared[name] then
    return false, "missing shared dict '" .. name .. "'"
  end

  return true
end


return {
  name = "graphql-rate-limiting-advanced",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { identifier = { description = "How to define the rate limit key. Can be `ip`, `credential`, `consumer`.", type = "string",
            one_of = { "ip", "credential", "consumer" },
            default = "consumer",
            required = true,
          }},
          { window_size = { description = "One or more window sizes to apply a limit to (defined in seconds).", type = "array",
            elements = {
              type = "number",
            },
            required = true,
          }},
          { window_type = { description = "Sets the time window to either `sliding` or `fixed`.", type = "string",
            one_of = { "fixed", "sliding" },
            default = "sliding",
          }},
          { limit = { description = "One or more requests-per-window limits to apply.", type = "array",
            elements = {
              type = "number",
            },
            required = true,
          }},
          { sync_rate = { description = "How often to sync counter data to the central data store. A value of 0 results in synchronous behavior; a value of -1 ignores sync behavior entirely and only stores counters in node memory. A value greater than 0 syncs the counters in that many number of seconds.",
            type = "number",
            required = true,
          }},
          { namespace = { description = "The rate limiting library namespace to use for this plugin instance. NOTE: For the plugin instances sharing the same namespace, all the configurations that are required for synchronizing counters, e.g. `strategy`, `redis`, `sync_rate`, `window_size`, `dictionary_name`, need to be the same.", type = "string",
            auto = true,
          }},
          { strategy = { description = "The rate-limiting strategy to use for retrieving and incrementing the limits.", type = "string",
            one_of = { "cluster", "redis", },
            default = "cluster",
            required = true,
          }},
          { dictionary_name = { description = "The shared dictionary where counters will be stored until the next sync cycle.", type = "string",
            default = "kong_rate_limiting_counters",
            required = true,
          }},
          { hide_client_headers = { description = "Optionally hide informative response headers. Available options: `true` or `false`.", type = "boolean",
            default = false,
          }},
          { cost_strategy = {
            description = "Strategy to use to evaluate query costs. Either `default` or `node_quantifier`.",
            type = "string",
            one_of = { "default", "node_quantifier" },
            default = "default",
          }},
          { score_factor = {
            description = "A scoring factor to multiply (or divide) the cost. The `score_factor` must always be greater than 0.",
            type = "number",
            required = false,
            default = 1.0,
            -- score_factor always greater than 0
            gt = 0
          }},
          { max_cost = {
            description = "A defined maximum cost per query. 0 means unlimited.",
            type = "number",
            required = false,
            default = 0,
          }},
          { redis = redis.config_schema},
        },
      },
    },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config

        if not config.limit or not config.window_size then
          return true
        end

        -- sort the window_size and limit arrays by limit
        -- first we create a temp table, each element of which is a pair of
        -- limit/window_size values. we then sort based on the limit element
        -- of this array of pairs. finally, we re-assign the plugin_t configuration
        -- elements directly based off the sorted temp table
        local t = {}
        for i, _ in ipairs(config.limit) do
          t[i] = { config.limit[i], config.window_size[i] }
        end

        table.sort(t, function(a, b) return tonumber(a[1]) < tonumber(b[1]) end)

        for i = 1, #t do
          config.limit[i] = tonumber(t[i][1])
          config.window_size[i] = tonumber(t[i][2])
        end

        if config.strategy == "cluster" and config.sync_rate ~= -1 then
          if kong.configuration.role ~= "traditional" then
            return nil, concat{ "Strategy 'cluster' is not supported with Hybrid deployments. ",
                                "If you did not specify the strategy, please use the 'redis' strategy ",
                                "or set 'sync_rate' to -1.", }
          end
          if kong.configuration.database == "off" then
            return nil, concat{ "Strategy 'cluster' is not supported with DB-less mode. ",
                                "If you did not specify the strategy, please use the 'redis' strategy ",
                                "or set 'sync_rate' to -1.", }
          end
        end

        if config.strategy == "redis" then
          if config.redis.host == ngx.null and
             config.redis.sentinel_addresses == ngx.null and
             config.redis.cluster_addresses == ngx.null then
            return nil, "No redis config provided"
          end
        end

        if entity.config.strategy == "memory" then
          local ok, err = check_shdict(entity.config.dictionary_name)
          if not ok then
            return nil, err
          end
        end

        if #entity.config.window_size ~= #entity.config.limit then
          return nil, "You must provide the same number of windows and limits"
        end

        return true
      end
    }},
  },
}
