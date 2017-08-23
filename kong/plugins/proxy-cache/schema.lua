local strategies = require "kong.plugins.proxy-cache.strategies"
local errors     = require "kong.dao.errors"


local function check_status(status_t)
  for i = 1, #status_t do
    local status = status_t[i]

    if status and (status < 100 or status > 999) then
      return false, "response_code must be within 100 - 999"
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
      default = { "text/plain" },
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
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    if plugin_t.strategy == "memory" then
      local ok, err = check_shdict(plugin_t.memory.dictionary_name)

      if not ok then
        return false, errors.schema(err)
      end
    end

    return true
  end,
}
