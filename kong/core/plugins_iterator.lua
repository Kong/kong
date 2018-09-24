local responses    = require "kong.tools.responses"
local singletons   = require "kong.singletons"


local setmetatable = setmetatable
local ipairs       = ipairs
local error        = error


-- Loads a plugin config from the datastore.
-- @return plugin config table or an empty sentinel table in case of a db-miss
local function load_plugin_into_memory(route_id,
                                       service_id,
                                       consumer_id,
                                       plugin_name,
                                       api_id)
  local rows, err = singletons.dao.plugins:find_all({
             name = plugin_name,
         route_id = route_id,
       service_id = service_id,
      consumer_id = consumer_id,
           api_id = api_id,
  }, true)
  if err then
    error(tostring(err))
  end

  if #rows > 0 then
    for _, row in ipairs(rows) do
      if    route_id == row.route_id    and
          service_id == row.service_id  and
         consumer_id == row.consumer_id and
              api_id == row.api_id      then
        return row
      end
    end
  end
  -- insert a cached value to not trigger too many DB queries.
  return { null = true }  -- works because: `.enabled == nil`
end



local function load_plugin_into_memory_ws(route_id,
                                          service_id,
                                          consumer_id,
                                          plugin_name,
                                          api_id,
                                          ctx,
                                          k)
  local ws_scope = ctx.workspaces or {}

  -- when there is no workspace, like in phase rewrite
  local plugin_cache_key = k

  local plugin, err = singletons.cache:get(plugin_cache_key,
                                           nil,
                                           load_plugin_into_memory,
                                           route_id,
                                           service_id,
                                           consumer_id,
                                           plugin_name,
                                           api_id)
  if #ws_scope == 0 then
    return plugin, err
  end

  -- check if plugin negatively cached by other phase where workspace not applicable
  if plugin and plugin.null then
    return plugin
  end

  -- check if plugin in cache for each workspace
  local found
  for _, ws in ipairs(ws_scope) do
    local plugin_cache_key = k .. ws.id

    plugin = singletons.cache.mlcache.lru:get(plugin_cache_key)
    if plugin then
      found = true

      if not plugin.null then
        return plugin
      end
    end

    if not plugin then
      local ttl
      ttl, err, plugin = singletons.cache:probe(plugin_cache_key)
      if err then
        return nil, err
      end

      singletons.cache.mlcache.lru:set(plugin_cache_key, plugin)

      if ttl then
        found = true

        if plugin and not plugin.null then
          return plugin
        end
      end
    end
  end

  -- if ttl present, plugin present in negative cache
  if found then
    return plugin
  end

  -- load plugin, here workspace scope can contain more than one workspace
  -- depending on with how many workspace, api being shared
  local plugin = load_plugin_into_memory(route_id,
                                         service_id,
                                         consumer_id,
                                         plugin_name,
                                         api_id)

  -- add positive and negative cache
  for _, ws in ipairs(ws_scope) do
    local plugin_cache_key = k .. ws.id

    local to_be_cached
    if plugin and not plugin.null and ws.id == plugin.workspace_id then
      -- positive cache
      to_be_cached = plugin
    else
      -- negative cache
      to_be_cached = { null = true }
    end

    local _, err = singletons.cache:get(plugin_cache_key, nil, function ()
      return to_be_cached
    end)
    if err then
      return nil, err
    end
  end

  return plugin
end


--- Load the configuration for a plugin entry in the DB.
-- Given an API, a Consumer and a plugin name, retrieve the plugin's
-- configuration if it exists. Results are cached in ngx.dict
-- @param[type=string] route_id ID of the route being proxied.
-- @param[type=string] service_id ID of the service being proxied.
-- @param[type=string] consumer_id ID of the Consumer making the request (if any).
-- @param[type=stirng] plugin_name Name of the plugin being tested for.
-- @param[type=string] api_id ID of the API being proxied.
-- @treturn table Plugin retrieved from the cache or database.
local function load_plugin_configuration(route_id,
                                         service_id,
                                         consumer_id,
                                         plugin_name,
                                         api_id,
                                         ctx,
                                         k)
  local plugin, err = load_plugin_into_memory_ws(route_id,
                                                 service_id,
                                                 consumer_id,
                                                 plugin_name,
                                                 api_id,
                                                 ctx,
                                                 k)
  if err then
    ctx.delay_response = false
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if plugin ~= nil and plugin.enabled then
    local plugin_ws = {
      id = plugin.workspace_id,
      name = plugin.workspace_name
    }

    ctx.workspaces = { plugin_ws }

    local cfg       = plugin.config or {}
    cfg.api_id      = plugin.api_id
    cfg.route_id    = plugin.route_id
    cfg.service_id  = plugin.service_id
    cfg.consumer_id = plugin.consumer_id

    return cfg
  end

  -- check for internal plugins
  local cfg = singletons.internal_proxies:get_plugin_config(
    route_id,
    service_id,
    consumer_id,
    plugin_name,
    api_id
  )

  if cfg then
    return cfg
  end
end


local function get_next(self)
  local i = self.i + 1

  local plugin = self.loaded_plugins[i]
  if not plugin then
    return nil
  end

  self.i = i

  if not self.configured_plugins[plugin.name] then
    return get_next(self)
  end

  local ctx = self.ctx

  -- load the plugin configuration in early phases
  if self.access_or_cert_ctx then

    local api          = self.api
    local route        = self.route
    local service      = self.service
    local consumer     = ctx.authenticated_consumer

    if consumer then
      local schema = plugin.schema
      if schema and schema.no_consumer then
        consumer = nil
      end
    end

    local      api_id = api      and      api.id or nil
    local    route_id = route    and    route.id or nil
    local  service_id = service  and  service.id or nil
    local consumer_id = consumer and consumer.id or nil

    local plugin_name = plugin.name

    local plugin_configuration

    repeat

      if route_id and service_id and consumer_id then
        local k = "plugins:"..plugin_name..":"..route_id..":"..service_id..":"..consumer_id.."::"
        plugin_configuration = load_plugin_configuration(route_id, service_id, consumer_id, plugin_name, nil, ctx, k)
        if plugin_configuration then
          break
        end
      end

      if route_id and consumer_id then
        local k = "plugins:"..plugin_name..":"..route_id.."::"..consumer_id.."::"
        plugin_configuration = load_plugin_configuration(route_id, nil, consumer_id, plugin_name, nil, ctx, k)
        if plugin_configuration then
          break
        end
      end

      if service_id and consumer_id then
        local k = "plugins:"..plugin_name.."::"..service_id..":"..consumer_id.."::"
        plugin_configuration = load_plugin_configuration(nil, service_id, consumer_id, plugin_name, nil, ctx, k)
        if plugin_configuration then
          break
        end
      end

      if api_id and consumer_id then
        local k = "plugins:"..plugin_name..":::"..consumer_id..":"..api_id..":"
        plugin_configuration = load_plugin_configuration(nil, nil, consumer_id, plugin_name, api_id, ctx, k)
        if plugin_configuration then
          break
        end
      end

      if route_id and service_id then
        local k = "plugins:"..plugin_name..":"..route_id..":"..service_id..":::"
        plugin_configuration = load_plugin_configuration(route_id, service_id, nil, plugin_name, nil, ctx, k)
        if plugin_configuration then
          break
        end
      end

      if consumer_id then
        local k = "plugins:"..plugin_name..":::"..consumer_id.."::"
        plugin_configuration = load_plugin_configuration(nil, nil, consumer_id, plugin_name, nil, ctx, k)
        if plugin_configuration then
          break
        end
      end

      if route_id then
        local k = "plugins:"..plugin_name..":"..route_id.."::::"
        plugin_configuration = load_plugin_configuration(route_id, nil, nil, plugin_name, nil, ctx, k)
        if plugin_configuration then
          break
        end
      end

      if service_id then
        local k = "plugins:"..plugin_name.."::"..service_id..":::"
        plugin_configuration = load_plugin_configuration(nil, service_id, nil, plugin_name, nil, ctx, k)
        if plugin_configuration then
          break
        end
      end

      if api_id then
        local k = "plugins:"..plugin_name.."::::"..api_id..":"
        plugin_configuration = load_plugin_configuration(nil, nil, nil, plugin_name, api_id, ctx, k)
        if plugin_configuration then
          break
        end
      end

      do
        local k = "plugins:"..plugin_name..":::::"
        plugin_configuration = load_plugin_configuration(nil, nil, nil, plugin_name, nil, ctx, k)
      end

    until true

    if plugin_configuration then
      ctx.plugins_for_request[plugin.name] = plugin_configuration
    end

    -- filter non-specific plugins out for internal services
    ctx.plugins_for_request = singletons.internal_proxies:filter_plugins(
      service_id, ctx.plugins_for_request)
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
local function iter_plugins_for_req(loaded_plugins, configured_plugins,
                                    access_or_cert_ctx)
  local ctx = ngx.ctx

  if not ctx.plugins_for_request then
    ctx.plugins_for_request = {}
  end

  local plugin_iter_state = {
    i                     = 0,
    ctx                   = ctx,
    api                   = ctx.api,
    route                 = ctx.route,
    service               = ctx.service,
    loaded_plugins        = loaded_plugins,
    configured_plugins    = configured_plugins,
    access_or_cert_ctx    = access_or_cert_ctx,
  }

  return setmetatable(plugin_iter_state, plugin_iter_mt)
end


return iter_plugins_for_req
