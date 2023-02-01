local workspaces   = require "kong.workspaces"
local constants    = require "kong.constants"
local warmup       = require "kong.cache.warmup"
local utils        = require "kong.tools.utils"
local tablepool    = require "tablepool"


local log          = ngx.log
local kong         = kong
local exit         = ngx.exit
local null         = ngx.null
local error        = error
local pairs        = pairs
local ipairs       = ipairs
local assert       = assert
local tostring     = tostring
local fetch_table  = tablepool.fetch
local release_table = tablepool.release


local TTL_ZERO     = { ttl = 0 }
local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }

local COMBO_R      = 1
local COMBO_S      = 2
local COMBO_RS     = 3
local COMBO_C      = 4
local COMBO_RC     = 5
local COMBO_SC     = 6
local COMBO_RSC    = 7
local COMBO_GLOBAL = 0

local ERR = ngx.ERR
local ERROR = ngx.ERROR


local subsystem = ngx.config.subsystem


local NON_COLLECTING_PHASES, DOWNSTREAM_PHASES, DOWNSTREAM_PHASES_COUNT, COLLECTING_PHASE do
  if subsystem == "stream" then
    NON_COLLECTING_PHASES = {
      "certificate",
      "log",
    }

    DOWNSTREAM_PHASES = {
      "log",
    }

    COLLECTING_PHASE = "preread"

  else
    NON_COLLECTING_PHASES = {
      "certificate",
      "rewrite",
      "response",
      "header_filter",
      "body_filter",
      "log",
    }

    DOWNSTREAM_PHASES = {
      "response",
      "header_filter",
      "body_filter",
      "log",
    }

    COLLECTING_PHASE = "access"
  end

  DOWNSTREAM_PHASES_COUNT = #DOWNSTREAM_PHASES
end

local PLUGINS_NS = "plugins." .. subsystem


local function get_table_for_ctx(ws)
  local tbl = fetch_table(PLUGINS_NS, 0, DOWNSTREAM_PHASES_COUNT + 2)
  if not tbl.initialized then
    for i = 1, DOWNSTREAM_PHASES_COUNT do
      tbl[DOWNSTREAM_PHASES[i]] = kong.table.new(ws.plugins[0] * 2, 1)
    end
    tbl.initialized = true
  end

  for i = 1, DOWNSTREAM_PHASES_COUNT do
    tbl[DOWNSTREAM_PHASES[i]][0] = 0
  end

  tbl.ws = ws

  return tbl
end


local function release(ctx)
  local plugins = ctx.plugins
  if plugins then
    release_table(PLUGINS_NS, plugins, true)
    ctx.plugins = nil
  end
end


local enabled_plugins
local loaded_plugins


local function get_loaded_plugins()
  return assert(kong.db.plugins:get_handlers())
end


local function should_process_plugin(plugin)
  if plugin.enabled then
    local c = constants.PROTOCOLS_WITH_SUBSYSTEM
    for _, protocol in ipairs(plugin.protocols) do
      if c[protocol] == subsystem then
        return true
      end
    end
  end
end


local next_seq = 0

-- Loads a plugin config from the datastore.
-- @return plugin config table or an empty sentinel table in case of a db-miss
local function load_plugin_from_db(key)
  local row, err = kong.db.plugins:select_by_cache_key(key)
  if err then
    return nil, tostring(err)
  end

  return row
end


local function get_plugin_config(plugin, name, ws_id)
  if not plugin or not plugin.enabled then
    return
  end

  local cfg = plugin.config or {}

  cfg.route_id    = plugin.route    and plugin.route.id
  cfg.service_id  = plugin.service  and plugin.service.id
  cfg.consumer_id = plugin.consumer and plugin.consumer.id
  cfg.plugin_instance_name = plugin.instance_name

  local key = kong.db.plugins:cache_key(name,
    cfg.route_id,
    cfg.service_id,
    cfg.consumer_id,
    nil,
    ws_id)

  if not cfg.__key__ then
    cfg.__key__ = key
    cfg.__seq__ = next_seq
    next_seq = next_seq + 1
  end

  return cfg
end


--- Load the configuration for a plugin entry.
-- Given a Route, Service, Consumer and a plugin name, retrieve the plugin's
-- configuration if it exists. Results are cached in ngx.dict
-- @param[type=string] name Name of the plugin being tested for configuration.
-- @param[type=string] route_id Id of the route being proxied.
-- @param[type=string] service_id Id of the service being proxied.
-- @param[type=string] consumer_id Id of the consumer making the request (if any).
-- @treturn table Plugin configuration, if retrieved.
local function load_configuration(ctx,
                                  name,
                                  route_id,
                                  service_id,
                                  consumer_id)
  local ws_id = workspaces.get_workspace_id(ctx) or kong.default_workspace
  local key = kong.db.plugins:cache_key(name,
                                        route_id,
                                        service_id,
                                        consumer_id,
                                        nil,
                                        ws_id)
  local plugin, err = kong.core_cache:get(key,
                                          nil,
                                          load_plugin_from_db,
                                          key)
  if err then
    ctx.delay_response = nil
    ctx.buffered_proxying = nil
    log(ERR, tostring(err))
    return exit(ERROR)
  end

  return get_plugin_config(plugin, name, ws_id)
end


local function load_configuration_through_combos(ctx, combos, plugin)
  local plugin_configuration
  local name = plugin.name

  local route    = ctx.route
  local service  = ctx.service
  local consumer = ctx.authenticated_consumer

  if route and plugin.handler.no_route then
    route = nil
  end
  if service and plugin.handler.no_service then
    service = nil
  end
  if consumer and plugin.handler.no_consumer then
    consumer = nil
  end

  local    route_id = route    and    route.id or nil
  local  service_id = service  and  service.id or nil
  local consumer_id = consumer and consumer.id or nil

  if kong.db.strategy == "off" then
    if route_id and service_id and consumer_id and combos[COMBO_RSC]
      and combos.rsc[route_id] and combos.rsc[route_id][service_id]
      and combos.rsc[route_id][service_id][consumer_id]
    then
      return combos.rsc[route_id][service_id][consumer_id]
    end

    if route_id and consumer_id and combos[COMBO_RC]
      and combos.rc[route_id] and combos.rc[route_id][consumer_id]
    then
      return combos.rc[route_id][consumer_id]
    end

    if service_id and consumer_id and combos[COMBO_SC]
      and combos.sc[service_id] and combos.sc[service_id][consumer_id]
    then
      return combos.sc[service_id][consumer_id]
    end

    if route_id and service_id and combos[COMBO_RS]
      and combos.rs[route_id] and combos.rs[route_id][service_id]
    then
      return combos.rs[route_id][service_id]
    end

    if consumer_id and combos[COMBO_C] and combos.c[consumer_id] then
      return combos.c[consumer_id]
    end

    if route_id and combos[COMBO_R] and combos.r[route_id] then
      return combos.r[route_id]
    end

    if service_id and combos[COMBO_S] and combos.s[service_id] then
      return combos.s[service_id]
    end

    if combos[COMBO_GLOBAL] then
      return combos[COMBO_GLOBAL]
    end

  else
    if route_id and service_id and consumer_id and combos[COMBO_RSC]
      and combos.both[route_id] == service_id
    then
      plugin_configuration = load_configuration(ctx, name, route_id, service_id,
                                                consumer_id)
      if plugin_configuration then
        return plugin_configuration
      end
    end

    if route_id and consumer_id and combos[COMBO_RC]
      and combos.routes[route_id]
    then
      plugin_configuration = load_configuration(ctx, name, route_id, nil,
                                                consumer_id)
      if plugin_configuration then
        return plugin_configuration
      end
    end

    if service_id and consumer_id and combos[COMBO_SC]
      and combos.services[service_id]
    then
      plugin_configuration = load_configuration(ctx, name, nil, service_id,
                                                consumer_id)
      if plugin_configuration then
        return plugin_configuration
      end
    end

    if route_id and service_id and combos[COMBO_RS]
      and combos.both[route_id] == service_id
    then
      plugin_configuration = load_configuration(ctx, name, route_id, service_id)
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

    if route_id and combos[COMBO_R] and combos.routes[route_id] then
      plugin_configuration = load_configuration(ctx, name, route_id)
      if plugin_configuration then
        return plugin_configuration
      end
    end

    if service_id and combos[COMBO_S] and combos.services[service_id] then
      plugin_configuration = load_configuration(ctx, name, nil, service_id)
      if plugin_configuration then
        return plugin_configuration
      end
    end

    if combos[COMBO_GLOBAL] then
      return load_configuration(ctx, name)
    end
  end
end


local function get_workspace(self, ctx)
  if not ctx then
    return self.ws[kong.default_workspace]
  end

  return self.ws[workspaces.get_workspace_id(ctx) or kong.default_workspace]
end


local function get_next_init_worker(plugins, i)
  local i = i + 1
  local plugin = plugins[i]
  if not plugin then
    return nil
  end

  if plugin.handler.init_worker then
    return i, plugin
  end

  return get_next_init_worker(plugins, i)
end


local function get_init_worker_iterator(self)
  if #self.loaded == 0 then
    return nil
  end

  return get_next_init_worker, self.loaded
end


local function get_next_global_or_collected_plugin(plugins, i)
  i = i + 2
  if i > plugins[0] then
    return nil
  end

  return i, plugins[i-1], plugins[i]
end


local function get_global_iterator(self, phase)
  local plugins = self.globals[phase]
  if plugins[0] == 0 then
    return nil
  end

  return get_next_global_or_collected_plugin, plugins
end


local function get_collected_iterator(self, phase, ctx)
  local plugins = ctx.plugins
  if plugins then
    plugins = plugins[phase]
    if plugins[0] == 0 then
      return nil
    end

    return get_next_global_or_collected_plugin, plugins
  end

  return get_global_iterator(self, phase)
end


local function get_next_and_collect(ctx, i)
  i = i + 1
  local ws = ctx.plugins.ws
  local plugins = ws.plugins
  if i > plugins[0] then
    return nil
  end

  local plugin = plugins[i]
  local name = plugin.name
  local cfg
  local combos = ws.combos[name]
  if combos then
    cfg = load_configuration_through_combos(ctx, combos, plugin)
    if cfg then
      local handler = plugin.handler
      local collected = ctx.plugins
      for j = 1, DOWNSTREAM_PHASES_COUNT do
        local phase = DOWNSTREAM_PHASES[j]
        if handler[phase] then
          local n = collected[phase][0] + 2
          collected[phase][0] = n
          collected[phase][n] = cfg
          collected[phase][n-1] = plugin
          if phase == "response" and not ctx.buffered_proxying then
            ctx.buffered_proxying = true
          end
        end
      end

      if handler[COLLECTING_PHASE] then
        return i, plugin, cfg
      end
    end
  end

  return get_next_and_collect(ctx, i)
end


local function get_collecting_iterator(self, ctx)
  local ws = get_workspace(self, ctx)
  if not ws then
    return nil
  end

  local plugins = ws.plugins
  if plugins[0] == 0 then
    return nil
  end

  ctx.plugins = get_table_for_ctx(ws)

  return get_next_and_collect, ctx
end


local PluginsIterator = {}


local function new_ws_data()
  return {
    plugins = { [0] = 0 },
    combos = {},
  }
end


function PluginsIterator.new(version)
  if kong.db.strategy ~= "off" then
    if not version then
      error("version must be given", 2)
    end
  end

  loaded_plugins = loaded_plugins or get_loaded_plugins()
  enabled_plugins = enabled_plugins or kong.configuration.loaded_plugins

  local ws_id = workspaces.get_workspace_id() or kong.default_workspace
  local ws = {
    [ws_id] = new_ws_data()
  }

  local cache_full
  local counter = 0
  local page_size = kong.db.plugins.pagination.max_page_size
  local globals do
    globals = {}
    for _, phase in ipairs(NON_COLLECTING_PHASES) do
      globals[phase] = { [0] = 0 }
    end
  end

  local has_plugins = false

  for plugin, err in kong.db.plugins:each(page_size, GLOBAL_QUERY_OPTS) do
    if err then
      return nil, err
    end

    local name = plugin.name
    if not enabled_plugins[name] then
      return nil, name .. " plugin is in use but not enabled"
    end

    local data = ws[plugin.ws_id]
    if not data then
      data = new_ws_data()
      ws[plugin.ws_id] = data
    end
    local plugins = data.plugins
    local combos = data.combos

    if kong.core_cache and counter > 0 and counter % page_size == 0 and kong.db.strategy ~= "off" then
      local new_version, err = kong.core_cache:get("plugins_iterator:version", TTL_ZERO, utils.uuid)
      if err then
        return nil, "failed to retrieve plugins iterator version: " .. err
      end

      if new_version ~= version then
        -- the plugins iterator rebuild is being done by a different process at
        -- the same time, stop here and let the other one go for it
        kong.log.info("plugins iterator was changed while rebuilding it")
        return
      end
    end

    if should_process_plugin(plugin) then
      if not has_plugins then
        has_plugins = true
      end

      plugins[name] = true

      local combo_key = (plugin.route    and 1 or 0)
                      + (plugin.service  and 2 or 0)
                      + (plugin.consumer and 4 or 0)

      local cfg
      if combo_key == COMBO_GLOBAL then
        cfg = get_plugin_config(plugin, name, ws_id)
        if cfg then
          globals[name] = cfg
        end
      end

      if kong.db.strategy == "off" then
        cfg = cfg or get_plugin_config(plugin, name, ws_id)
        if cfg then
          combos[name]     = combos[name]     or {}
          combos[name].rsc = combos[name].rsc or {}
          combos[name].rc  = combos[name].rc  or {}
          combos[name].sc  = combos[name].sc  or {}
          combos[name].rs  = combos[name].rs  or {}
          combos[name].c   = combos[name].c   or {}
          combos[name].r   = combos[name].r   or {}
          combos[name].s   = combos[name].s   or {}

          combos[name][combo_key] = cfg

          if cfg.route_id and cfg.service_id and cfg.consumer_id then
            combos[name].rsc[cfg.route_id] =
            combos[name].rsc[cfg.route_id] or {}
            combos[name].rsc[cfg.route_id][cfg.service_id] =
            combos[name].rsc[cfg.route_id][cfg.service_id] or {}
            combos[name].rsc[cfg.route_id][cfg.service_id][cfg.consumer_id] = cfg

          elseif cfg.route_id and cfg.consumer_id then
            combos[name].rc[cfg.route_id] =
            combos[name].rc[cfg.route_id] or {}
            combos[name].rc[cfg.route_id][cfg.consumer_id] = cfg

          elseif cfg.service_id and cfg.consumer_id then
            combos[name].sc[cfg.service_id] =
            combos[name].sc[cfg.service_id] or {}
            combos[name].sc[cfg.service_id][cfg.consumer_id] = cfg

          elseif cfg.route_id and cfg.service_id then
            combos[name].rs[cfg.route_id] =
            combos[name].rs[cfg.route_id] or {}
            combos[name].rs[cfg.route_id][cfg.service_id] = cfg

          elseif cfg.consumer_id then
            combos[name].c[cfg.consumer_id] = cfg

          elseif cfg.route_id then
            combos[name].r[cfg.route_id] = cfg

          elseif cfg.service_id then
            combos[name].s[cfg.service_id] = cfg
          end
        end

      else
        if version == "init" and not cache_full then
          local ok
          ok, err = warmup.single_entity(kong.db.plugins, plugin)
          if not ok then
            if err ~= "no memory" then
              return nil, err
            end

            kong.log.warn("cache warmup of plugins has been stopped because ",
                          "cache memory is exhausted, please consider increasing ",
                          "the value of 'mem_cache_size' (currently at ",
                           kong.configuration.mem_cache_size, ")")

            cache_full = true
          end
        end

        combos[name]          = combos[name]          or {}
        combos[name].both     = combos[name].both     or {}
        combos[name].routes   = combos[name].routes   or {}
        combos[name].services = combos[name].services or {}

        combos[name][combo_key] = true

        if plugin.route and plugin.service then
          combos[name].both[plugin.route.id] = plugin.service.id

        elseif plugin.route then
          combos[name].routes[plugin.route.id] = true

        elseif plugin.service then
          combos[name].services[plugin.service.id] = true
        end
      end
    end

    counter = counter + 1
  end

  for _, plugin in ipairs(loaded_plugins) do
    local name = plugin.name
    for _, data in pairs(ws) do
      local plugins = data.plugins
      if plugins[name] then
        local n = plugins[0] + 1
        plugins[n] = plugin
        plugins[0] = n
        plugins[name] = nil
      end
    end

    local cfg = globals[name]
    if cfg then
      globals[name] = nil
      for _, phase in ipairs(NON_COLLECTING_PHASES) do
        if plugin.handler[phase] then
          local plugins = globals[phase]
          local n = plugins[0] + 2
          plugins[0] = n
          plugins[n] = cfg
          plugins[n-1] = plugin
        end
      end
    end
  end

  return {
    version = version,
    ws = ws,
    loaded = loaded_plugins,
    globals = globals,
    get_init_worker_iterator = get_init_worker_iterator,
    get_global_iterator = get_global_iterator,
    get_collecting_iterator = get_collecting_iterator,
    get_collected_iterator = get_collected_iterator,
    has_plugins = has_plugins,
    release = release,
  }
end


return PluginsIterator
