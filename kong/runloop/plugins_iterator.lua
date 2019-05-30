local BasePlugin   = require "kong.plugins.base_plugin"
local constants    = require "kong.constants"
local reports      = require "kong.reports"


local kong         = kong
local type         = type
local error        = error
local pairs        = pairs
local ipairs       = ipairs
local assert       = assert
local tostring     = tostring


local COMBO_R      = 1
local COMBO_S      = 2
local COMBO_RS     = 3
local COMBO_C      = 4
local COMBO_RC     = 5
local COMBO_SC     = 6
local COMBO_RSC    = 7
local COMBO_GLOBAL = 0


local MUST_LOAD_CONFIGURATION_IN_PHASES = {
  preread     = true,
  certificate = true,
  rewrite     = true,
  access      = true,
  content     = true,
}


local subsystem = ngx.config.subsystem


local loaded_plugins


local function get_loaded_plugins()
  local loaded = assert(kong.db.plugins:get_handlers())

  if kong.configuration.anonymous_reports then
    reports.configure_ping(kong.configuration)
    reports.add_ping_value("database_version", kong.db.infos.db_ver)
    reports.toggle(true)

    loaded[#loaded + 1] = {
      name = "reports",
      handler = reports,
    }
  end

  return loaded
end


local function should_process_plugin(plugin)
  local c = constants.PROTOCOLS_WITH_SUBSYSTEM
  for _, protocol in ipairs(plugin.protocols) do
    if c[protocol] == subsystem then
      return true
    end
  end
end



-- Loads a plugin config from the datastore.
-- @return plugin config table or an empty sentinel table in case of a db-miss
local function load_plugin_from_db(key)
  local row, err = kong.db.plugins:select_by_cache_key(key)
  if err then
    return nil, tostring(err)
  end

  return row
end


--- Load the configuration for a plugin entry.
-- Given a Route, Service, Consumer and a plugin name, retrieve the plugin's
-- configuration if it exists. Results are cached in ngx.dict
-- @param[type=string] name Name of the plugin being tested for configuration.
-- @param[type=string] route_id Id of the route being proxied.
-- @param[type=string] service_id Id of the service being proxied.
-- @param[type=string] consumer_id Id of the donsumer making the request (if any).
-- @treturn table Plugin configuration, if retrieved.
local function load_configuration(ctx,
                                  name,
                                  route_id,
                                  service_id,
                                  consumer_id)
  local key = kong.db.plugins:cache_key(name,
                                        route_id,
                                        service_id,
                                        consumer_id)
  local plugin, err = kong.cache:get(key,
                                     nil,
                                     load_plugin_from_db,
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


local function load_configuration_through_combos(ctx, combos, plugin)
  local plugin_configuration
  local name = plugin.name

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

  if route_id and service_id and consumer_id and combos[COMBO_RSC] then
    plugin_configuration = load_configuration(ctx, name, route_id, service_id, consumer_id)
    if plugin_configuration then
      return plugin_configuration
    end
  end

  if route_id and consumer_id and combos[COMBO_RC] then
    plugin_configuration = load_configuration(ctx, name, route_id, nil, consumer_id)
    if plugin_configuration then
      return plugin_configuration
    end
  end

  if service_id and consumer_id and combos[COMBO_SC] then
    plugin_configuration = load_configuration(ctx, name, nil, service_id, consumer_id)
    if plugin_configuration then
      return plugin_configuration
    end
  end

  if route_id and service_id and combos[COMBO_RS] then
    plugin_configuration = load_configuration(ctx, name, route_id, service_id, nil)
    if plugin_configuration then
      return plugin_configuration
    end
  end

  if consumer_id and combos[COMBO_C] then
    plugin_configuration = load_configuration(ctx, name, nil, nil, consumer_id)
    if plugin_configuration then
      return plugin_configuration
    end
  end

  if route_id and combos[COMBO_R] then
    plugin_configuration = load_configuration(ctx, name, route_id, nil, nil)
    if plugin_configuration then
      return plugin_configuration
    end
  end

  if service_id and combos[COMBO_S] then
    plugin_configuration = load_configuration(ctx, name, nil, service_id, nil)
    if plugin_configuration then
      return plugin_configuration
    end
  end

  if combos[COMBO_GLOBAL] then
    return load_configuration(ctx, name, nil, nil, nil)
  end
end


local function get_next(self)
  local i = self.i + 1

  local plugin = self.iterator.loaded[i]
  if not plugin then
    return nil
  end

  self.i = i

  if not self.ctx then
    if self.iterator.phases[self.phase][plugin.name] then
      return plugin
    end

    return get_next(self)
  end

  if not self.iterator.map[plugin.name] then
    return get_next(self)
  end

  local ctx = self.ctx

  if MUST_LOAD_CONFIGURATION_IN_PHASES[self.phase] then
    local combos = self.iterator.combos[plugin.name]
    if combos then
      local cfg = load_configuration_through_combos(ctx, combos, plugin)
      if cfg then
        ctx.plugins[plugin.name] = cfg
      end
    end
  end

  local phase = self.iterator.phases[self.phase]
  if phase and phase[plugin.name]
  and (ctx.plugins[plugin.name] or self.phase == "init_worker") then
    return plugin, ctx.plugins[plugin.name]
  end

  return get_next(self) -- Load next plugin
end


local PluginsIterator = {}


--- Plugins Iterator
--
-- Iterate over the plugin loaded for a request, stored in
--`ngx.ctx.plugins`.
--
-- @param[type=string] phase Plugins iterator execution phase
-- @param[type=table] ctx Nginx context table
-- @treturn function iterator
local function iterate(self, phase, ctx)
  -- no ctx, we are in init_worker phase
  if ctx and not ctx.plugins then
    ctx.plugins = {}
  end

  local iteration = {
    iterator = self,
    phase = phase,
    ctx = ctx,
    i = 0,
  }

  return get_next, iteration
end


function PluginsIterator.new(version)
  if not version then
    error("version must be given", 2)
  end

  loaded_plugins = loaded_plugins or get_loaded_plugins()

  local map = {}
  local combos = {}
  local phases
  if subsystem == "stream" then
    phases = {
      init_worker = {},
      preread     = {},
      log         = {},
    }
  else
    phases = {
      init_worker   = {},
      certificate   = {},
      rewrite       = {},
      access        = {},
      header_filter = {},
      body_filter   = {},
      log           = {},
    }
  end

  for plugin, err in kong.db.plugins:each(1000) do
    if err then
      return nil, err
    end

    if should_process_plugin(plugin) then
      map[plugin.name] = true

      local combo_key = (plugin.route    and 1 or 0)
                      + (plugin.service  and 2 or 0)
                      + (plugin.consumer and 4 or 0)

      combos[plugin.name] = combos[plugin.name] or {}
      combos[plugin.name][combo_key] = true
    end
  end

  for _, plugin in ipairs(loaded_plugins) do
    for phase_name, phase in pairs(phases) do
      if phase_name == "init_worker" or combos[plugin.name] then
        local phase_handler = plugin.handler[phase_name]
        if type(phase_handler) == "function"
        and phase_handler ~= BasePlugin[phase_name] then
          phase[plugin.name] = true
        end
      end
    end
  end

  return {
    map = map,
    version = version,
    phases = phases,
    combos = combos,
    loaded = loaded_plugins,
    iterate = iterate,
  }
end


return PluginsIterator
