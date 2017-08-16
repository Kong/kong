local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"

local setmetatable = setmetatable

-- Loads a plugin config from the datastore.
-- @return plugin config table or an empty sentinel table in case of a db-miss
local function load_plugin_into_memory(api_id, consumer_id, plugin_name)
  local rows, err = singletons.dao.plugins:find_all {
    api_id = api_id,
    consumer_id = consumer_id,
    name = plugin_name
  }
  if err then
    return nil, err
  end

  if #rows > 0 then
    for _, row in ipairs(rows) do
      if api_id == row.api_id and consumer_id == row.consumer_id then
        return row
      end
    end
  end
  -- insert a cached value to not trigger too many DB queries.
  return {null = true}  -- works because: `.enabled == nil`
end

--- Load the configuration for a plugin entry in the DB.
-- Given an API, a Consumer and a plugin name, retrieve the plugin's
-- configuration if it exists. Results are cached in ngx.dict
-- @param[type=string] api_id ID of the API being proxied.
-- @param[type=string] consumer_id ID of the Consumer making the request (if any).
-- @param[type=stirng] plugin_name Name of the plugin being tested for.
-- @treturn table Plugin retrieved from the cache or database.
local function load_plugin_configuration(api_id, consumer_id, plugin_name)
  local plugin_cache_key = singletons.dao.plugins:cache_key(plugin_name,
                                                            api_id,
                                                            consumer_id)
  local plugin, err = singletons.cache:get(plugin_cache_key, nil,
                                           load_plugin_into_memory,
                                           api_id, consumer_id, plugin_name)
  if err then
    responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  if plugin ~= nil and plugin.enabled then
    return plugin.config or {}
  end
end

local function get_next(self)
  local i = self.i
  i = i + 1

  local plugin = self.loaded_plugins[i]
  if not plugin then
    return nil
  end

  self.i = i

  local ctx = self.ctx

  -- load the plugin configuration in early phases
  if self.access_or_cert_ctx then
    local api = self.api
    local plugin_configuration

    local consumer = ctx.authenticated_consumer
    if consumer then
      local consumer_id = consumer.id
      local schema      = plugin.schema

      if schema and not schema.no_consumer then
        if api then
          plugin_configuration = load_plugin_configuration(api.id, consumer_id, plugin.name)
        end
        if not plugin_configuration then
          plugin_configuration = load_plugin_configuration(nil, consumer_id, plugin.name)
        end
      end
    end

    if not plugin_configuration then
      -- Search API specific, or global
      if api then
        plugin_configuration = load_plugin_configuration(api.id, nil, plugin.name)
      end
      if not plugin_configuration then
        plugin_configuration = load_plugin_configuration(nil, nil, plugin.name)
      end
    end

    ctx.plugins_for_request[plugin.name] = plugin_configuration
  end

  -- return the plugin configuration
  local plugins_for_request = ctx.plugins_for_request
  if plugins_for_request[plugin.name] then
    return plugin, plugins_for_request[plugin.name]
  end

  return get_next(self) -- Load next plugin
end

local plugin_iter_mt = { __call = get_next }

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

  local plugin_iter_state = {
    i                     = 0,
    ctx                   = ctx,
    api                   = ctx.api,
    loaded_plugins        = loaded_plugins,
    access_or_cert_ctx    = access_or_cert_ctx,
  }

  return setmetatable(plugin_iter_state, plugin_iter_mt)
end

return iter_plugins_for_req
