local strategies = require "kong.plugins.proxy-cache.strategies"
local redis      = require "kong.enterprise_edition.redis"
local errors     = require "kong.dao.errors"


local function check_status(status_t)
  if #status_t == 0 then
    return false, "response_code must contain at least one value"
  end

  for i = 1, #status_t do
    local status = tonumber(status_t[i])
    if not status then
      return false, "response_code value must be an integer"
    end

    if status % 1 ~= 0 or status < 100 or status > 999 then
      return false, "response_code must be an integer within 100 - 999"
    end
  end

  return true
end


local function check_ttl(ttl)
  if ttl and (ttl <= 0) then
    return false, "cache_ttl must be a positive number"
  end

  return true
end


local function check_shdict(name)
  if not ngx.shared[name] then
    return false, "missing shared dict '" .. name .. "'"
  end

  return true
end


local memory_schema = {
  fields = {
    dictionary_name = {
      type = "string",
      default = "kong_cache",
    },
  },
}


return {
  fields = {
    response_code = {
      type = "array",
      default = { 200, 301, 404 },
      func = check_status,
      required = true,
    },
    request_method = {
      type = "array",
      default = { "GET", "HEAD" },
      required = true,
    },
    content_type = {
      type = "array",
      default = { "text/plain","application/json" },
      required = true,
    },
    cache_ttl = {
      type = "number",
      default = 300,
      func = check_ttl,
    },
    strategy = {
      type = "string",
      enum = strategies.STRATEGY_TYPES,
      required = true,
    },
    cache_control = {
      type = "boolean",
      default = false,
      required = true,
    },
    storage_ttl = {
      type = "number",
    },
    memory = {
      type = "table",
      schema = memory_schema,
    },
    redis = {
      type = "table",
      schema = redis.config_schema,
    },
    vary_query_params = {
      type = "array",
    },
    vary_headers = {
      type = "array",
    },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    if plugin_t.strategy == "memory" then
      local ok, err = check_shdict(plugin_t.memory.dictionary_name)

      if not ok then
        return false, errors.schema(err)
      end
    elseif plugin_t.strategy == "redis" then
      if not plugin_t.redis then
        return false, errors.schema("No redis config provided")
      end
    end

    if plugin_t.response_code then
      for i = 1, #plugin_t.response_code do
        plugin_t.response_code[i] = tonumber(plugin_t.response_code[i])
      end
    end

    if plugin_t.vary_headers then
      for i, v in ipairs(plugin_t.vary_headers) do
        plugin_t.vary_headers[i] = string.lower(v)
      end

      table.sort(plugin_t.vary_headers)
    end

    if plugin_t.vary_query_params then
      table.sort(plugin_t.vary_query_params)
    end

    return true
  end,
}
