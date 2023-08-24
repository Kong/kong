-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local strategies = require "kong.plugins.proxy-cache-advanced.strategies"
local redis      = require "kong.enterprise_edition.redis"
local typedefs   = require "kong.db.schema.typedefs"



local ngx = ngx


local function check_shdict(name)
  if not ngx.shared[name] then
    return false, "missing shared dict '" .. name .. "'"
  end

  return true
end


return {
  name = "proxy-cache-advanced",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { response_code = { description = "Upstream response status code considered cacheable. The integers must be a value between 100 and 900.", type = "array",
            default = { 200, 301, 404 },
            elements = { type = "integer", between = {100, 900} },
            len_min = 1,
            required = true,
          }},
          { request_method = { description = "Downstream request methods considered cacheable. Available options: `HEAD`, `GET`, `POST`, `PATCH`, `PUT`.", type = "array",
            default = { "GET", "HEAD" },
            elements = {
              type = "string",
              one_of = { "HEAD", "GET", "POST", "PATCH", "PUT" },
            },
            required = true
          }},
          { content_type = { description = "Upstream response content types considered cacheable. The plugin performs an **exact match** against each specified value; for example, if the upstream is expected to respond with a `application/json; charset=utf-8` content-type, the plugin configuration must contain said value or a `Bypass` cache status is returned.", type = "array",
            default = { "text/plain","application/json" },
            elements = { type = "string" },
            required = true,
          }},
          { cache_ttl = { description = "TTL in seconds of cache entities.", type = "integer",
            default = 300,
            gt = 0,
          }},
          { strategy = { description = "The backing data store in which to hold cache entities. Accepted values are: `memory` and `redis`.", type = "string",
            one_of = strategies.STRATEGY_TYPES,
            required = true,
          }},
          { cache_control = { description = "When enabled, respect the Cache-Control behaviors defined in RFC7234.", type = "boolean",
            default = false,
            required = true,
          }},
          { ignore_uri_case = {
            type = "boolean",
            description = "Determines whether to treat URIs as case sensitive. By default, case sensitivity is enabled. If set to true, requests are cached while ignoring case sensitivity in the URI.",
            default = false,
            required = false,
          }},
          { storage_ttl = { description = "Number of seconds to keep resources in the storage backend. This value is independent of `cache_ttl` or resource TTLs defined by Cache-Control behaviors.", type = "integer",
          }},
          { memory = {
            type = "record",
            fields = {
              { dictionary_name = { description = "The name of the shared dictionary in which to hold cache entities when the memory strategy is selected. Note that this dictionary currently must be defined manually in the Kong Nginx template.", type = "string",
                required = true,
                default = "kong_db_cache",
              }},
            },
          }},
          { vary_query_params = { description = "Relevant query parameters considered for the cache key. If undefined, all params are taken into consideration.", type = "array",
            elements = { type = "string" },
          }},
          { vary_headers = { description = "Relevant headers considered for the cache key. If undefined, none of the headers are taken into consideration.", type = "array",
            elements = { type = "string" },
          }},
          { response_headers = {
            description = "Caching related diagnostic headers that should be included in cached responses",
            type = "record",
            fields = {
              { age  = {type = "boolean",  default = true} },
              { ["X-Cache-Status"]  = {type = "boolean",  default = true} },
              { ["X-Cache-Key"]  = {type = "boolean",  default = true} },
            },
          }},
          { redis = redis.config_schema }, -- redis schema is provided by
                                           -- Kong Enterprise, since it's useful
                                           -- for other plugins (e.g., rate-limiting)
          { bypass_on_err = { description = "Unhandled errors while trying to retrieve a cache entry (such as redis down) are resolved with `Bypass`, with the request going upstream.", type = "boolean",
            default = false,
          }},
        },
      }
    },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config

        if config.strategy == "memory" then
          local ok, err = check_shdict(config.memory.dictionary_name)
          if not ok then
            return nil, err
          end

        elseif entity.config.strategy == "redis" then
          if config.redis.host == ngx.null
             and config.redis.sentinel_addresses == ngx.null
             and config.redis.cluster_addresses == ngx.null then
            return nil, "No redis config provided"
          end
        end

        return true
      end
    }},
  },
}
