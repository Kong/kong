local cache = require "kong.tools.database_cache"
local constants = require "kong.constants"
local responses = require "kong.tools.responses"

local table_remove = table.remove
local table_insert = table.insert
local ipairs = ipairs

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
    local rows, err = dao.plugins:find_by_keys {
      api_id = api_id,
      consumer_id = consumer_id ~= nil and consumer_id or constants.DATABASE_NULL_ID,
      name = plugin_name
    }
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    if #rows > 0 then
      return table_remove(rows, 1)
    else
      -- insert a cached value to not trigger too many DB queries.
      -- for now, this will lock the cache for the expiraiton duration.
      return {null = true}
    end
  end)

  if plugin ~= nil and plugin.enabled then
    return plugin.config or {}
  end
end

local function load_plugins_for_req(loaded_plugins)
  if ngx.ctx.plugins_for_request == nil then
    local t = {}
    -- Build an array of plugins that must be executed for this particular request.
    -- A plugin is considered to be executed if there is a row in the DB which contains:
    -- 1. the API id (contained in ngx.ctx.api.id, retrived by the core resolver)
    -- 2. a Consumer id, in which case it overrides any previous plugin found in 1.
    --    this use case will be treated once the authentication plugins have run (access phase).
    -- Such a row will contain a `config` value, which is a table.
    if ngx.ctx.api ~= nil then
      for _, plugin in ipairs(loaded_plugins) do
        local plugin_configuration = load_plugin_configuration(ngx.ctx.api.id, nil, plugin.name)
        if plugin_configuration ~= nil then
          table_insert(t, {plugin, plugin_configuration})
        end
      end
    end

    ngx.ctx.plugins_for_request = t
  end
end

--- Plugins for request iterator.
-- Iterate over the plugin loaded for a request, stored in `ngx.ctx.plugins_for_request`.
-- @param[type=string] context_name Name of the current nginx context. We don't use `ngx.get_phase()` simply because we can avoid it.
-- @treturn function iterator
local function iter_plugins_for_req(loaded_plugins, context_name)
  -- In case previous contexts did not run, we need to handle
  -- the case when plugins have not been fetched for a given request.
  -- This will simply make it so the look gets skipped if no API is set in the context
  load_plugins_for_req(loaded_plugins)

  local i = 0

  -- Iterate on plugins to execute for this request until
  -- a plugin with a handler for the given context is found.
  local function get_next()
    i = i + 1
    local p = ngx.ctx.plugins_for_request[i]
    if p == nil then
      return
    end

    local plugin, plugin_configuration = p[1], p[2]
    if plugin.handler[context_name] == nil then
      ngx.log(ngx.DEBUG, "No handler for "..context_name.." phase on "..plugin.name.." plugin")
      return get_next()
    end

    return plugin, plugin_configuration
  end

  return function()
    local plugin, plugin_configuration = get_next()

    -- Check if any Consumer was authenticated during the access phase.
    -- If so, retrieve the configuration for this Consumer which overrides
    -- the API-wide configuration.
    if plugin ~= nil and context_name == "access" then
      local consumer_id = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.consumer_id or nil
      if consumer_id ~= nil then
        local consumer_plugin_configuration = load_plugin_configuration(ngx.ctx.api.id, consumer_id, plugin.name)
        if consumer_plugin_configuration ~= nil then
          -- This Consumer has a special configuration when this plugin gets executed.
          -- Override this plugin's configuration for this request.
          plugin_configuration = consumer_plugin_configuration
          ngx.ctx.plugins_for_request[i][2] = consumer_plugin_configuration
        end
      end
    end

    return plugin, plugin_configuration
  end
end

return iter_plugins_for_req
