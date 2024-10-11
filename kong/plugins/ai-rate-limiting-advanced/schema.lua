-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis  = require "kong.enterprise_edition.tools.redis.v2"
local typedefs = require "kong.db.schema.typedefs"
local loadstring = loadstring

local ngx = ngx
local null = ngx.null
local concat = table.concat

local function validate_function(fun)
  local _, err = loadstring(fun)
  if err then
    return false, "error parsing prompt function: " .. err
  end

  return true
end

local llm_provider_schema = {
  type = "record",
  fields = {
    { window_size = { description = "The window size to apply a limit (defined in seconds).",
            type = "number",
            required = true,
    }},
    { name = { description = "The LLM provider to which the rate limit applies.",
            type = "string",
            one_of = { "openai", "azure", "anthropic", "cohere", "mistral", "llama2", "bedrock", "gemini", "requestPrompt" }, 
            required = true,
    }},
    { limit = { description = "The limit applies to the LLM provider within the defined window size. It used the query cost from the tokens to increment the counter.",
            type = "number",
            required = true,
    }}
  }
}

return {
  name = "ai-rate-limiting-advanced",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { identifier = { description = "The type of identifier used to generate the rate limit key. Defines the scope used to increment the rate limiting counters. Can be `ip`, `credential`, `consumer`, `service`, `header`, `path` or `consumer-group`.", type = "string",
            one_of = { "ip", "credential", "consumer", "service", "header", "path", "consumer-group" },
            default = "consumer",
            required = true,
          }},
          { window_type = { description = "Sets the time window type to either `sliding` (default) or `fixed`. Sliding windows apply the rate limiting logic while taking into account previous hit rates (from the window that immediately precedes the current) using a dynamic weight. Fixed windows consist of buckets that are statically assigned to a definitive time range, each request is mapped to only one fixed window based on its timestamp and will affect only that window's counters.", type = "string",
            one_of = { "fixed", "sliding" },
            default = "sliding",
          }},
          { sync_rate = { description = "How often to sync counter data to the central data store. A value of 0 results in synchronous behavior; a value of -1 ignores sync behavior entirely and only stores counters in node memory. A value greater than 0 will sync the counters in the specified number of seconds. The minimum allowed interval is 0.02 seconds (20ms).", type = "number",
          }},
          { llm_providers = { description = "The provider config. Takes an array of `name`, `limit` and `window size` values.", type = "array",
            elements = llm_provider_schema,
            required = true,
          }},
          { strategy = { description = "The rate-limiting strategy to use for retrieving and incrementing the limits. Available values are: `local` and `cluster`.", type = "string",
            one_of = { "cluster", "redis", "local" },
            default = "local",
            required = true,
          }},
          { dictionary_name = { description = "The shared dictionary where counters are stored. When the plugin is configured to synchronize counter data externally (that is `config.strategy` is `cluster` or `redis` and `config.sync_rate` isn't `-1`), this dictionary serves as a buffer to populate counters in the data store on each synchronization cycle.", type = "string",
            default = "kong_rate_limiting_counters",
            required = true,
          }},
          { hide_client_headers = { description = "Optionally hide informative response headers that would otherwise provide information about the current status of limits and counters.", type = "boolean",
            default = false,
          }},
          { retry_after_jitter_max = { description = "The upper bound of a jitter (random delay) in seconds to be added to the `Retry-After` header of denied requests (status = `429`) in order to prevent all the clients from coming back at the same time. The lower bound of the jitter is `0`; in this case, the `Retry-After` header is equal to the `RateLimit-Reset` header.", -- in seconds
            type = "number",
            default = 0,
          }},
          { header_name = typedefs.header_name, },
          { path = typedefs.path },
          { redis = redis.config_schema},
          { disable_penalty = { description = "If set to `true`, this doesn't count denied requests (status = `429`). If set to `false`, all requests, including denied ones, are counted. This parameter only affects the `sliding` window_type and the request prompt provider.", type = "boolean",
            default = false,
          }},
          { request_prompt_count_function = { description = "If defined, it use custom function to count requests for the request prompt provider", type = "string",
            custom_validator = validate_function,
            required = false,
          }},
          { error_code = { description = "Set a custom error code to return when the rate limit is exceeded.", type = "number", default = 429, gt = 0, }, },
          { error_message = { description = "Set a custom error message to return when the rate limit is exceeded.", type = "string", default = "AI token rate limit exceeded for provider(s): ", }, },
          { error_hide_providers = { description = "Optionally hide informative response that would otherwise provide information about the provider in the error message.", type = "boolean", default = false, }, },
          { tokens_count_strategy = { description = "What tokens to use for cost calculation. Available values are: `total_tokens` `prompt_tokens`, `completion_tokens` or `cost`.", type = "string",
            one_of = { "total_tokens", "prompt_tokens", "completion_tokens", "cost" },
            default = "total_tokens",
            required = true,
          }},
        },
      },
    }
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config
        local providersList = {}

        for _, provider in ipairs(config.llm_providers) do
          if providersList[provider.name] then
            return nil, "Provider '" .. provider.name .. "' is not unique"
          else
              providersList[provider.name] = true
          end

          if provider.name == "requestPrompt" then
            if config.request_prompt_count_function == null then
              return nil, "You must provide request prompt count function when using requestPrompt provider"
            end
          end
        end

        if config.strategy == "cluster" and config.sync_rate ~= -1 then
          if kong.configuration.role ~= "traditional" or kong.configuration.database == "off" then
            return nil, concat{ "[ai-rate-limiting-advanced] ",
                                "strategy 'cluster' is not supported with Hybrid deployments or DB-less mode. ",
                                "If you did not specify the strategy, please use 'redis' strategy, 'local' strategy ",
                                "or set 'sync_rate' to -1.", }
          end
        end

        if config.strategy == "redis" then
          if config.redis.host == null and
             config.redis.sentinel_nodes == null and
             config.redis.cluster_nodes == null then
            return nil, "No redis config provided"
          end
        end

        if config.strategy == "local" then
          if config.sync_rate ~= null and config.sync_rate > -1 then
            return nil, "sync_rate cannot be configured when using a local strategy"
          end
        else
          if config.sync_rate == null then
            return nil, "sync_rate is required if not using a local strategy"
          end
        end

        if config.identifier == "header" then
          if config.header_name == null then
            return nil, "No header name provided"
          end
        end

        if config.identifier == "path" then
          if config.path == null then
            return nil, "No path provided"
          end
        end

        if config.retry_after_jitter_max < 0 then
          return nil, "Non-negative retry_after_jitter_max value is expected"
        end

        -- a decimal between 0 and 1 messes with internal time calculations
        if config.sync_rate ~= null then
          if config.sync_rate > 0 and config.sync_rate < 0.02 then
            return nil, "Config option 'sync_rate' must not be a decimal between 0 and 0.02"
          end
        end

        return true
      end
    }},
  },
}
