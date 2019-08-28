local BasePlugin   = require "kong.plugins.base_plugin"
local constants    = require "kong.constants"
local reports      = require "kong.reports"


local kong         = kong
local singletons   = require "kong.singletons"
local tracing      = require "kong.tracing"

local type         = type
local error        = error
local pairs        = pairs
local ipairs       = ipairs
local assert       = assert
local tostring     = tostring


local EMPTY_T      = {}


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
  local row, err = kong.db.plugins:select_by_cache_key(key, {include_ws = true})
  if err then
    return nil, tostring(err)
  end

  return row
end


-- TODO relying on `select_by_cache_key_migrating` is likely not the best
-- alternative here; for one, it might (will?) be removed in a future release;
-- second, it can likely be optimized for our purposes here (fetching a plugin
-- without a workspace available)
local function load_plugin_into_memory_global_scope(key)
  local row, err = kong.db.plugins.strategy:select_by_cache_key_migrating(key)
  if err then
    return nil, err
  end

  return row and kong.db.plugins:row_to_entity(row)
end


local function load_plugin_into_memory_ws(ctx, key)
  local ws_scope = ctx.workspaces or {}

  -- query with "global cache key" - no workspace attached to it
  local plugin, err, hit_level = kong.cache:get(key,
                                                nil,
                                                load_plugin_into_memory_global_scope,
                                                key)
  if err then
    return nil, err
  end

  -- if plugin is nil and hit_level is 1 or 2, it means the value came
  -- from L1 or L2 cache, so it's was negative cached
  if not plugin and hit_level < 3 then
    return plugin
  end

  -- if workspace scope is empty, we can't query by cache_key, so
  -- attempt to find a plugin for the given combination of name/service/route/
  -- consumer (pre-0.15 way)
  if #ws_scope == 0 then
    return plugin
  end

  local found

  -- iterate for all workspaces in the context; if a plugin is found for some of
  -- them, return it; otherwise, cache a negative entry
  for _, ws in ipairs(ws_scope) do
    local plugin_cache_key = key .. ws.id

    -- attempt finding the plugin in the L1 (LRU) cache
    plugin = singletons.cache.mlcache.lru:get(plugin_cache_key)
    if plugin then
      found = true

      if plugin.enabled ~= nil then -- using .enabled as a sentinel for positive cache -
        return plugin        -- if it was a negative cache, such field would not
                             -- be there
      end
    end

    -- if plugin is nil, that means it wasn't found so far, so do an L2 (shm) lookup
    if not plugin then
      local ttl
      ttl, err, plugin = singletons.cache:probe(plugin_cache_key)
      if err then
        return nil, err
      end

      -- :set causes the value to be written back to L1, so subsequent requests
      -- will find a cached entry there (positive or negative)
      singletons.cache.mlcache.lru:set(plugin_cache_key, plugin)

      if ttl then -- ttl means a cached value was found (positive or negative)
        found = true

        if plugin and plugin.enabled ~= nil then -- if positive, return (again, using
                                          -- `.enabled` as a sentinel)
          return plugin
        end
      end
    end
  end

  -- plugin is negative cached
  if found then
     return plugin
  end

  for _, ws in ipairs(ws_scope) do
    local plugin_cache_key = key .. ws.id
    plugin = load_plugin_from_db(plugin_cache_key)

    if plugin and  ws.id == plugin.workspace_id then

      -- +ve cache plugin and return
      -- no further DB call required
      local _, err = kong.cache:get(plugin_cache_key, nil, function ()
        return plugin
      end)
      if err then
        return nil, err
      end

      return plugin
    end

    -- -ve cache plugin and continue
    local _, err = kong.cache:get(plugin_cache_key, nil, function ()
      return plugin
    end)
    if err then
      return nil, err
    end
  end

  return plugin
end


--- Load the configuration for a plugin entry in the DB.
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
  local trace = tracing.trace("load_plugin_config", { plugin_name = name })

  local key = kong.db.plugins:cache_key(name,
                                        route_id,
                                        service_id,
                                        consumer_id,
                                        nil, -- placeholder for api_id
                                        true)
  local ws_scope = ctx.workspaces or {}
  local plugin, err = load_plugin_into_memory_ws(ctx, key)
  trace:finish()

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

  -- when workspace scope is not empty or nil:
  -- narrow the scope to workspace where plugin is found
  -- add the workspace to plugin_configuration
  if #ws_scope > 0 then
    local plugin_ws = {
      id = plugin.workspace_id,
      name = plugin.workspace_name
    }
    ctx.workspaces = { plugin_ws }
    cfg.workspace = plugin_ws
  end

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

  local plugin = self.loaded[i]
  if not plugin then
    return nil
  end

  self.i = i

  local name = plugin.name
  if not self.ctx then
    if self.phases[name] then
      return plugin
    end

    return get_next(self)
  end

  if not self.map[name] then
    return get_next(self)
  end

  local ctx = self.ctx
  local plugins = ctx.plugins

  if self.configure then
    local combos = self.combos[name]
    if combos then
      local cfg = load_configuration_through_combos(ctx, combos, plugin)
      if cfg then
        plugins[name] = cfg
      end
    end
  end

  -- return the plugin configuration
  local plugin_configuration = ctx.plugins[plugin.name]
  if plugin_configuration then

    -- when workspace scope not empty return plugin
    -- only if it has workspace information.
    -- even the global plugin will have workspace detail as it is re-fetched
    -- plugins in access phase
    if ctx.workspaces then
      if plugin_configuration.workspace then

        -- Added in EE:
        local phase = self.phases
        if phase and phase[plugin.name]
        and (ctx.plugins[plugin.name] or self.phase == "init_worker") then
          return plugin, ctx.plugins[plugin.name]
        end

        return get_next(self)
      end

      -- ignore global plugin fetched in earlier phase
      -- as it has not been applied in current workspace
      return get_next(self)
    end

    -- Added in EE:
    local phase = self.phase
    if phase and phase[plugin.name]
    and (ctx.plugins[plugin.name] or self.phase == "init_worker") then
      return plugin, ctx.plugins[plugin.name]
    end

    -- when workspace scope empty, return global plugin
    -- fetched in earlier phase
    return get_next(self) -- Load next plugin

  -- XXX EE
  -- if self.phases[name] and plugins[name] then
  --   return plugin, plugins[name]
  -- XXX EE/
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
    -- XXX EE
    -- iterator = self,
    -- phase = phase,
    configure = MUST_LOAD_CONFIGURATION_IN_PHASES[phase],
    loaded = self.loaded,
    phases = self.phases[phase] or EMPTY_T,
    combos = self.combos,
    map = self.map,
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
