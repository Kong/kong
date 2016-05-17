local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"
local pl_tablex = require "pl.tablex"

local empty = pl_tablex.readonly {}

--- Load the configuration for a plugin entry in the DB.
-- Given an API, a Consumer and a plugin name, retrieve the plugin's
-- configuration if it exists. Results are cached in ngx.dict
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
-- Iterate over the plugin loaded for a request, stored in
-- `ngx.ctx.plugins_for_request`.
-- @param[type=boolean] access_or_cert_ctx Tells if the context
-- is access_by_lua_block. We don't use `ngx.get_phase()` simply because we can
-- avoid it.
-- @treturn function iterator
local function iter_plugins_for_req(loaded_plugins, access_or_cert_ctx)
  local ctx = ngx.ctx

  if not ctx.plugins_for_request then
    ctx.plugins_for_request = {}
  end

  local i = 0

  local function get_next()
    i = i + 1
    local plugin = loaded_plugins[i]
    if plugin and ctx.api then
      -- load the plugin configuration in early phases
      if access_or_cert_ctx then
        ctx.plugins_for_request[plugin.name] = load_plugin_configuration(ctx.api.id, nil, plugin.name)

        local consumer_id = (ctx.authenticated_credential or empty).consumer_id
        if consumer_id and not plugin.schema.no_consumer then
          local consumer_plugin_configuration = load_plugin_configuration(ctx.api.id, consumer_id, plugin.name)
          if consumer_plugin_configuration then
            ctx.plugins_for_request[plugin.name] = consumer_plugin_configuration
          end
        end
      end

      -- return the plugin configuration
      if ctx.plugins_for_request[plugin.name] then
        return plugin, ctx.plugins_for_request[plugin.name]
      end

      return get_next() -- Load next plugin
    end
  end

  return get_next
end

return iter_plugins_for_req
