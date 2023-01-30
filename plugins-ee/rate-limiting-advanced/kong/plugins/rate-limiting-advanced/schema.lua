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
  name = "rate-limiting-advanced",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { identifier = {
            type = "string",
            one_of = { "ip", "credential", "consumer", "service", "header", "path" },
            default = "consumer",
            required = true,
          }},
          { window_size = {
            type = "array",
            elements = {
              type = "number",
            },
            required = true,
          }},
          { window_type = {
            type = "string",
            one_of = { "fixed", "sliding" },
            default = "sliding",
          }},
          { limit = {
            type = "array",
            elements = {
              type = "number",
            },
            required = true,
          }},
          { sync_rate = {
            type = "number",
          }},
          { namespace = {
            type = "string",
            auto = true,
            required = true,
          }},
          { strategy = {
            type = "string",
            one_of = { "cluster", "redis", "local" },
            default = "local",
            required = true,
          }},
          { dictionary_name = {
            type = "string",
            default = "kong_rate_limiting_counters",
            required = true,
          }},
          { hide_client_headers = {
            type = "boolean",
            default = false,
          }},
          { retry_after_jitter_max = { -- in seconds
            type = "number",
            default = 0,
          }},
          { header_name = typedefs.header_name, },
          { path = typedefs.path },
          { redis = redis.config_schema},
          { enforce_consumer_groups = {
            type = "boolean",
            default = false,
          }},
          { consumer_groups = {
            type = "array",
            elements = {
              type = "string",
            },
          }},
          { disable_penalty = {
            type = "boolean",
            default = false,
          }},
          { error_code = { type = "number", default = 429, gt = 0, }, },
          { error_message = { type = "string", default = "API rate limit exceeded", }, },
        },
      },
    }
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config

        if not config.limit or not config.window_size then
          return true
        end

        if #config.window_size ~= #config.limit then
          return nil, "You must provide the same number of windows and limits"
        end

        -- sort the window_size and limit arrays by limit
        -- first we create a temp table, each element of which is a pair of
        -- limit/window_size values. we then sort based on the limit element
        -- of this array of pairs. finally, we re-assign the configuration
        -- elements directly based off the sorted temp table
        local t = {}
        for i, v in ipairs(config.limit) do
          t[i] = { config.limit[i], config.window_size[i] }
        end

        table.sort(t, function(a, b) return tonumber(a[1]) < tonumber(b[1]) end)

        for i = 1, #t do
          config.limit[i] = tonumber(t[i][1])
          config.window_size[i] = tonumber(t[i][2])
        end

        if config.strategy == "cluster" and config.sync_rate ~= -1 then
          if kong.configuration.role ~= "traditional" or kong.configuration.database == "off" then
            return nil, concat{ "[rate-limiting-advanced] ",
                                "strategy 'cluster' is not supported with Hybrid deployments or DB-less mode. ",
                                "If you did not specify the strategy, please use 'redis' strategy, 'local' strategy ",
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

        if config.strategy == "local" then
          if config.sync_rate ~= ngx.null and config.sync_rate > -1 then
            return nil, "sync_rate cannot be configured when using a local strategy"
          end
          config.sync_rate = -1
        else
          if config.sync_rate == ngx.null then
            return nil, "sync_rate is required if not using a local strategy"
          end
        end

        if config.dictionary_name ~= nil then
          local ok, err = check_shdict(config.dictionary_name)
          if not ok then
            return nil, err
          end
        end

        if config.identifier == "header" then
          if config.header_name == ngx.null then
            return nil, "No header name provided"
          end
        end

        if config.identifier == "path" then
          if config.path == ngx.null then
            return nil, "No path provided"
          end
        end

        if config.retry_after_jitter_max < 0 then
          return nil, "Non-negative retry_after_jitter_max value is expected"
        end

        -- a decimal between 0 and 1 messes with internal time calculations
        if config.sync_rate > 0 and config.sync_rate < 0.02 then
          return nil, "Config option 'sync_rate' must not be a decimal between 0 and 0.02"
        end

        if config.enforce_consumer_groups then
          if config.consumer_groups == ngx.null then
            return nil, "No consumer groups provided"
          end
        end
        return true
      end
    }},
  },
}
