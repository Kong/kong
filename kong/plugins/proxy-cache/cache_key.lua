local _M = {}

local EMPTY = {}


local function keys(t)
  local res = {}
  for k, _ in pairs(t) do
    res[#res+1] = k
  end

  return res
end


-- Return a string with the format "key=value(:key=value)*" of the
-- actual keys and values in args that are in vary_fields.
--
-- The elements are sorted so we get consistent cache actual_keys no matter
-- the order in which params came in the request
local function generate_key_from(args, vary_fields)
  local cache_key = {}

  for _, field in pairs(vary_fields or {}) do
    local arg = args[field]
    if arg then
      if type(arg) == "table" then
        table.sort(arg)
        table.insert(cache_key, field .. "=" .. table.concat(arg, ","))

      else
        table.insert(cache_key, field .. "=" .. arg)
      end
    end
  end

  return table.concat(cache_key, ":")
end


-- Return the component of cache_key for vary_query_params in params
--
-- If no vary_query_params are configured in the plugin, return
-- all of them.
function _M.params_key(params, plugin_config)
  if not (plugin_config.vary_query_params or EMPTY)[1] then
    local actual_keys = keys(params)
    table.sort(actual_keys)
    return generate_key_from(params, actual_keys)
  end

  return generate_key_from(params, plugin_config.vary_query_params)
end


-- Return the component of cache_key for vary_headers in params
--
-- If no vary_query_params are configured in the plugin, return
-- the empty string.
function _M.headers_key(headers, plugin_config)
  if not (plugin_config.vary_headers or EMPTY)[1] then
    return ""
  end

  return generate_key_from(headers, plugin_config.vary_headers)
end


return _M
