local singletons = require "kong.singletons"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"

--- Load the configuration for a plugin entry in the DB.
-- Given an API, a Consumer and a plugin name, retrieve the plugin's configuration if it exists.
-- Results are cached in ngx.dict
-- @param[type=string] api_id ID of the API being proxied.
-- @param[type=string] consumer_id ID of the Consumer making the request (if any).
-- @param[type=stirng] plugin_name Name of the plugin being tested for.
-- @treturn table Plugin retrieved from the cache or database.
local function load_plugin_configuration(api_id, consumer_id, plugin_name)
  local cache_key = cache.plugin_key(plugin_name, api_id, consumer_id)
  local plugin = cache.get_or_set(cache_key, function()
    local rows, err = singletons.dao.plugins:find_all {
      api_id = api_id,
      consumer_id = consumer_id,
      name = plugin_name
    }
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    if #rows > 0 then
      if consumer_id == nil then
        for _, row in ipairs(rows) do
          if row.consumer_id == nil then
            return row
          end
        end
      else
        return rows[1]
      end
    else
      -- insert a cached value to not trigger too many DB queries.
      return {null = true}
    end
  end)

  if plugin ~= nil and plugin.enabled then
    return plugin.config or {}
  end
end

--- Plugins for request iterator.
-- Iterate over the plugin loaded for a request, stored in `ngx.ctx.plugins_for_request`.
-- @param[type=boolean] is_access_or_certificate_context Tells if the context is access_by_lua_block. We don't use `ngx.get_phase()` simply because we can avoid it.
-- @treturn function iterator
local function iter_plugins_for_req(loaded_plugins, is_access_or_certificate_context)
  if not ngx.ctx.plugins_for_request then
    ngx.ctx.plugins_for_request = {}
  end

  local i = 0
  local function get_next_plugin()
    i = i + 1
    return loaded_plugins[i]
  end

  local function get_next()
    local plugin = get_next_plugin()
    if plugin and ngx.ctx.api then
      if is_access_or_certificate_context then
        ngx.ctx.plugins_for_request[plugin.name] = load_plugin_configuration(ngx.ctx.api.id, nil, plugin.name)

        local consumer_id = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.consumer_id or nil
        if consumer_id and not plugin.schema.no_consumer then
          local consumer_plugin_configuration = load_plugin_configuration(ngx.ctx.api.id, consumer_id, plugin.name)
          if consumer_plugin_configuration then
            ngx.ctx.plugins_for_request[plugin.name] = consumer_plugin_configuration
          end
        end
      end

      -- Return the configuration
      if ngx.ctx.plugins_for_request[plugin.name] then
        return plugin, ngx.ctx.plugins_for_request[plugin.name]
      end

      return get_next() -- Load next plugin
    end
  end

  return function()
    return get_next()
  end
end

return iter_plugins_for_req
