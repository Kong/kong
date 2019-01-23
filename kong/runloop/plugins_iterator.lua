local kong         = kong
local setmetatable = setmetatable


-- Loads a plugin config from the datastore.
-- @return plugin config table or an empty sentinel table in case of a db-miss
local function load_plugin_into_memory(key)
  local row, err = kong.db.plugins:select_by_cache_key(key)
  if err then
    return nil, tostring(err)
  end

  return row
end


--- Load the configuration for a plugin entry in the DB.
-- Given a Route, Service, Consumer and a plugin name, retrieve the plugin's
-- configuration if it exists. Results are cached in ngx.dict
-- @param[type=string] route_id ID of the route being proxied.
-- @param[type=string] service_id ID of the service being proxied.
-- @param[type=string] consumer_id ID of the Consumer making the request (if any).
-- @param[type=stirng] plugin_name Name of the plugin being tested for.
-- @treturn table Plugin retrieved from the cache or database.
local function load_plugin_configuration(ctx,
                                         route_id,
                                         service_id,
                                         consumer_id,
                                         plugin_name)
  local key = kong.db.plugins:cache_key(plugin_name,
                                        route_id,
                                        service_id,
                                        consumer_id)

  local plugin, err = kong.cache:get(key,
                                     nil,
                                     load_plugin_into_memory,
                                     key)
  if err then
    ctx.delay_response = false
    ngx.log(ngx.ERR, tostring(err))
    return ngx.exit(ngx.ERROR)
  end

  if not plugin or not plugin.enabled then
    return
  end

  if plugin.run_on ~= "all" then
    if ctx.is_service_mesh_request then
      if plugin.run_on == "first" then
        return
      end

    else
      if plugin.run_on == "second" then
        return
      end
    end
  end

  local cfg = plugin.config or {}

  cfg.route_id    = plugin.route and plugin.route.id
  cfg.service_id  = plugin.service and plugin.service.id
  cfg.consumer_id = plugin.consumer and plugin.consumer.id

  return cfg
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

    local route        = self.route
    local service      = self.service
    local consumer     = ctx.authenticated_consumer

    if route and plugin.no_route then
      route = nil
    end
    if service and plugin.no_service then
      service = nil
    end
    if consumer and plugin.no_consumer then
      consumer = nil
    end

    local    route_id = route    and    route.id or nil
    local  service_id = service  and  service.id or nil
    local consumer_id = consumer and consumer.id or nil

    local plugin_name = plugin.name

    local plugin_configuration

    repeat

      if route_id and service_id and consumer_id then
        plugin_configuration = load_plugin_configuration(ctx, route_id, service_id, consumer_id, plugin_name)
        if plugin_configuration then
          break
        end
      end

      if route_id and consumer_id then
        plugin_configuration = load_plugin_configuration(ctx, route_id, nil, consumer_id, plugin_name)
        if plugin_configuration then
          break
        end
      end

      if service_id and consumer_id then
        plugin_configuration = load_plugin_configuration(ctx, nil, service_id, consumer_id, plugin_name)
        if plugin_configuration then
          break
        end
      end

      if route_id and service_id then
        plugin_configuration = load_plugin_configuration(ctx, route_id, service_id, nil, plugin_name)
        if plugin_configuration then
          break
        end
      end

      if consumer_id then
        plugin_configuration = load_plugin_configuration(ctx, nil, nil, consumer_id, plugin_name)
        if plugin_configuration then
          break
        end
      end

      if route_id then
        plugin_configuration = load_plugin_configuration(ctx, route_id, nil, nil, plugin_name)
        if plugin_configuration then
          break
        end
      end

      if service_id then
        plugin_configuration = load_plugin_configuration(ctx, nil, service_id, nil, plugin_name)
        if plugin_configuration then
          break
        end
      end

      plugin_configuration = load_plugin_configuration(ctx, nil, nil, nil, plugin_name)

    until true

    if plugin_configuration then
      ctx.plugins_for_request[plugin.name] = plugin_configuration
    end
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
local function iter_plugins_for_req(ctx, loaded_plugins, configured_plugins,
                                    access_or_cert_ctx)
  if not ctx.plugins_for_request then
    ctx.plugins_for_request = {}
  end

  local plugin_iter_state = {
    i                     = 0,
    ctx                   = ctx,
    route                 = ctx.route,
    service               = ctx.service,
    loaded_plugins        = loaded_plugins,
    configured_plugins    = configured_plugins,
    access_or_cert_ctx    = access_or_cert_ctx,
  }

  return setmetatable(plugin_iter_state, plugin_iter_mt)
end


return iter_plugins_for_req
