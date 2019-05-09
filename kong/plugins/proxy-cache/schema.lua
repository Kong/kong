local strategies = require "kong.plugins.proxy-cache.strategies"

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
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config

        if config.strategy == "memory" then
          local ok, err = check_shdict(config.memory.dictionary_name)
          if not ok then
            return nil, err
          end

        end

        return true
      end
    }},
  },
}
