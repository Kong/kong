local typedefs = require "kong.db.schema.typedefs"
local strategies = require "kong.plugins.proxy-cache.strategies"



local ngx = ngx


local function check_shdict(name)
  if not ngx.shared[name] then
    return false, "missing shared dict '" .. name .. "'"
  end

  return true
end


return {
  name = "proxy-cache",
  fields = {
    { config = {
        type = "record",
        fields = {
          { response_code = {
            type = "array",
            default = { 200, 301, 404 },
            elements = { type = "integer", between = {100, 900} },
            len_min = 1,
            required = true,
          }},
          { request_method = {
            type = "array",
            default = { "GET", "HEAD" },
            elements = {
              type = "string",
              one_of = { "HEAD", "GET", "POST", "PATCH", "PUT" },
            },
            required = true
          }},
          { content_type = {
            type = "array",
            default = { "text/plain","application/json" },
            elements = { type = "string" },
            required = true,
          }},
          { cache_ttl = {
            type = "integer",
            default = 300,
            gt = 0,
          }},
          { strategy = {
            type = "string",
            one_of = strategies.STRATEGY_TYPES,
            required = true,
          }},
          { cache_control = {
            type = "boolean",
            default = false,
            required = true,
          }},
          { storage_ttl = {
            type = "integer",
          }},
          { memory = {
            type = "record",
            fields = {
              { dictionary_name = {
                type = "string",
                required = true,
                default = "kong_db_cache",
              }},
            },
          }},
          { redis = {
            type = "record",
            fields = {
              { host = typedefs.host },
              { port = typedefs.port({ default = 6379 }), },
              { password = { type = "string", len_min = 0 }, },
              { timeout = { type = "number", default = 2000, }, },
              { database = { type = "integer", default = 0 }, },
            },
          }},
          { vary_query_params = {
            type = "array",
            elements = { type = "string" },
          }},
          { vary_headers = {
            type = "array",
            elements = { type = "string" },
          }},
        },
      }
    },
  },

  entity_checks = {
    { conditional = {
      if_field = "config.strategy", if_match = { eq = "redis" },
      then_field = "config.redis.host", then_match = { required = true },
    } },
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config

        if config.strategy == "memory" then
          local ok, err = check_shdict(config.memory.dictionary_name)
          if not ok then
            return nil, err
          end
          return true

        elseif config.strategy == "redis" then
          return true
        end

        return nil, "unknown strategy"
      end
    }},
  },
}
