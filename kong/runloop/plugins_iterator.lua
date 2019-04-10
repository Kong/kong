local kong         = kong
local setmetatable = setmetatable


local COMBO_R      = 1
local COMBO_S      = 2
local COMBO_RS     = 3
local COMBO_C      = 4
local COMBO_RC     = 5
local COMBO_SC     = 6
local COMBO_RSC    = 7
local COMBO_GLOBAL = 0


local LOAD_CONFIGURATION_PHASES = {
  preread     = true,
  certificate = true,
  rewrite     = true,
  access      = true,
  content     = true,
}


--- Load the configuration for a plugin entry.
-- Given a Route, Service, Consumer and a plugin name, retrieve the plugin's
-- configuration if it exists.
-- @param[type=table] the iterator object.
-- @param[type=string] name Name of the plugin being tested for configuration.
-- @param[type=string] route_id Id of the route being proxied.
-- @param[type=string] service_id Id of the service being proxied.
-- @param[type=string] consumer_id Id of the donsumer making the request (if any).
-- @treturn table Plugin configuration, if retrieved.
local function load_configuration(self,
                                  name,
                                  route_id,
                                  service_id,
                                  consumer_id)
  local key = kong.db.plugins:cache_key(name,
                                        route_id,
                                        service_id,
                                        consumer_id)

  local plugin = self.plugins.cache[key]
  if not plugin or not plugin.enabled then
    return
  end

  if plugin.run_on ~= "all" then
    if self.ctx.is_service_mesh_request then
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

  cfg.route_id    = plugin.route    and plugin.route.id
  cfg.service_id  = plugin.service  and plugin.service.id
  cfg.consumer_id = plugin.consumer and plugin.consumer.id

  return cfg
end


local function get_next(self)
  local i = self.i + 1

  local plugin = self.plugins.loaded[i]
  if not plugin then
    return nil
  end

  self.i = i

  if not self.plugins.map[plugin.name] then
    return get_next(self)
  end

  local ctx = self.ctx

  if self.load then
    local combos   = self.plugins.combos

    local route    = ctx.route
    local service  = ctx.service
    local consumer = ctx.authenticated_consumer

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

    local plugin_configuration

    repeat

      if combos[COMBO_RSC] and route_id and service_id and consumer_id then
        plugin_configuration = load_configuration(self, plugin.name, route_id, service_id, consumer_id)
        if plugin_configuration then
          break
        end
      end

      if combos[COMBO_RC] and route_id and consumer_id then
        plugin_configuration = load_configuration(self, plugin.name, route_id, nil, consumer_id)
        if plugin_configuration then
          break
        end
      end

      if combos[COMBO_SC] and service_id and consumer_id then
        plugin_configuration = load_configuration(self, plugin.name, nil, service_id, consumer_id)
        if plugin_configuration then
          break
        end
      end

      if combos[COMBO_RS] and route_id and service_id then
        plugin_configuration = load_configuration(self, plugin.name, route_id, service_id)
        if plugin_configuration then
          break
        end
      end

      if combos[COMBO_C] and consumer_id then
        plugin_configuration = load_configuration(self, plugin.name, nil, nil, consumer_id)
        if plugin_configuration then
          break
        end
      end

      if combos[COMBO_R] and route_id then
        plugin_configuration = load_configuration(self, plugin.name, route_id)
        if plugin_configuration then
          break
        end
      end

      if combos[COMBO_S] and service_id then
        plugin_configuration = load_configuration(self, plugin.name, nil, service_id)
        if plugin_configuration then
          break
        end
      end

      if combos[COMBO_GLOBAL] then
        plugin_configuration = load_configuration(self, plugin.name)
      end

    until true

    if plugin_configuration then
      ctx.plugins[plugin.name] = plugin_configuration
    end
  end

  -- return the plugin configuration
  if ctx.plugins[plugin.name] then
    return plugin, ctx.plugins[plugin.name]
  end

  return get_next(self) -- Load next plugin
end


local plugins_iterator_mt = { __call = get_next }


--- Plugins Iterator
--
-- Iterate over the plugin loaded for a request, stored in
-- `ngx.ctx.plugins`.
--
-- @param[type=table] ctx Nginx context table
-- @param[type=string] phase Plugins iterator execution phase
-- @param[type=table] plugins Plugins table
-- @treturn function iterator
local function plugins_iterator(ctx, phase, plugins)
  if not ctx.plugins then
    ctx.plugins = {}
  end

  local plugins_iterator_state = {
    i       = 0,
    ctx     = ctx,
    load    = LOAD_CONFIGURATION_PHASES[phase],
    plugins = plugins,
  }

  return setmetatable(plugins_iterator_state, plugins_iterator_mt)
end


return plugins_iterator
