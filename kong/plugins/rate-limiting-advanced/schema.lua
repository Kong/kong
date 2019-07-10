local redis  = require "kong.enterprise_edition.redis"


local function check_shdict(name)
  if not ngx.shared[name] then
    return false, "missing shared dict '" .. name .. "'"
  end

  return true
end


return {
  name = "rate-limiting-advanced",
  fields = {
    { config = {
        type = "record",
        fields = {
          { identifier = {
            type = "string",
            one_of = { "ip", "credential", "consumer" },
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
            required = true,
          }},
          { namespace = {
            type = "string",
            auto = true,
          }},
          { strategy = {
            type = "string",
            one_of = { "cluster", "redis", },
            default = "cluster",
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
          { redis = redis.config_schema},
        },
      },
    }
  },

  check = function(entity)
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
    for i, v in ipairs(config.limit) do
      t[i] = { config.limit[i], config.window_size[i] }
    end

    table.sort(t, function(a, b) return tonumber(a[1]) < tonumber(b[1]) end)

    for i = 1, #t do
      config.limit[i] = tonumber(t[i][1])
      config.window_size[i] = tonumber(t[i][2])
    end

    return true
  end,

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        local config = entity.config

        if config.strategy == "memory" then
          local ok, err = check_shdict(config.dictionary_name)
          if not ok then
            return nil, err
          end

        elseif config.strategy == "redis" then
          if config.redis.host == ngx.null and
             config.redis.sentinel_addresses == ngx.null and
             config.redis.cluster_addresses == ngx.null then
            return nil, "No redis config provided"
          end
        end

        if #config.window_size ~= #config.limit then
          return nil, "You must provide the same number of windows and limits"
        end

        return true
      end
    }},
  },
}
