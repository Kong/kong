-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local workspaces = require "kong.workspaces"
local constants = require "kong.constants"
local utils = require "kong.tools.utils"
local tablepool = require "tablepool"


local isempty = require("table.isempty")
local topsort_plugins = require("kong.db.schema.topsort_plugins")


local kong = kong
local error = error
local assert = assert
local var = ngx.var
local null = ngx.null
local pcall = pcall
local subsystem = ngx.config.subsystem
local pairs = pairs
local ipairs = ipairs
local format = string.format
local fetch_table = tablepool.fetch
local release_table = tablepool.release


local TTL_ZERO = { ttl = 0 }
local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }


local NON_COLLECTING_PHASES, DOWNSTREAM_PHASES, DOWNSTREAM_PHASES_COUNT, COLLECTING_PHASE, CONFIGURE_PHASE,
      WS_DOWNSTREAM_PHASES, WS_DOWNSTREAM_PHASES_COUNT, WS_COLLECTING_PHASE
do
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

    WS_DOWNSTREAM_PHASES = {
      "ws_client_frame",
      "ws_upstream_frame",
      "ws_close",
      "log",
    }

    WS_DOWNSTREAM_PHASES_COUNT = #WS_DOWNSTREAM_PHASES

    COLLECTING_PHASE = "access"
    WS_COLLECTING_PHASE = "ws_handshake"
  end

  DOWNSTREAM_PHASES_COUNT = #DOWNSTREAM_PHASES
  CONFIGURE_PHASE = "configure"
end


local PLUGINS_NS = "plugins." .. subsystem
local ENABLED_PLUGINS
local LOADED_PLUGINS
local CONFIGURABLE_PLUGINS


local PluginsIterator = {}


---
-- Build a compound key by string formatting route_id, service_id, and consumer_id with colons as separators.
--
-- @function build_compound_key
-- @tparam string|nil route_id The route identifier. If `nil`, an empty string is used.
-- @tparam string|nil service_id The service identifier. If `nil`, an empty string is used.
-- @tparam string|nil consumer_id The consumer identifier. If `nil`, an empty string is used.
-- @tparam string|nil consumer_group_id The consumer group identifier. If `nil`, an empty string is used.
-- @treturn string The compound key, in the format `route_id:service_id:consumer_id`.
local function build_compound_key(route_id, service_id, consumer_id, consumer_group_id)
  return format("%s:%s:%s:%s", route_id or "", service_id or "", consumer_id or "", consumer_group_id or "")
end


local PLUGIN_GLOBAL_KEY = build_compound_key() -- all nil


local function get_table_for_ctx(ws, websocket)
  local tbl
  local downstream_phases
  local downstream_phases_count
  if websocket then
    downstream_phases = WS_DOWNSTREAM_PHASES
    downstream_phases_count = WS_DOWNSTREAM_PHASES_COUNT
    tbl = kong.table.new(0, downstream_phases_count + 2)
  else
    downstream_phases = DOWNSTREAM_PHASES
    downstream_phases_count = DOWNSTREAM_PHASES_COUNT
    tbl = fetch_table(PLUGINS_NS, 0, downstream_phases_count + 2)
  end

  if not tbl.initialized then
    local count = ws and ws.plugins[0] * 2 or 0
    for i = 1, downstream_phases_count do
      tbl[downstream_phases[i]] = kong.table.new(count, 1)
    end
    if websocket then
      tbl.websocket = true
    else
      tbl.initialized = true
    end
  end

  for i = 1, downstream_phases_count do
    tbl[downstream_phases[i]][0] = 0
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


local function get_loaded_plugins()
  return assert(kong.db.plugins:get_handlers())
end


local function get_configurable_plugins()
  local i = 0
  local plugins_with_configure_phase = {}
  for _, plugin in ipairs(LOADED_PLUGINS) do
    if plugin.handler[CONFIGURE_PHASE] then
      i = i + 1
      local name = plugin.name
      plugins_with_configure_phase[name] = true
      plugins_with_configure_phase[i] = plugin
    end
  end
  return plugins_with_configure_phase
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


local function get_plugin_config(plugin, name, ws_id)
  if not plugin or not plugin.enabled then
    return
  end

  local cfg = plugin.config or {}

  cfg.ordering = plugin.ordering
  cfg.route_id = plugin.route and plugin.route.id
  cfg.service_id = plugin.service and plugin.service.id
  cfg.consumer_id = plugin.consumer and plugin.consumer.id
  cfg.consumer_group_id = plugin.consumer_group and plugin.consumer_group.id
  cfg.plugin_instance_name = plugin.instance_name
  cfg.__plugin_id = plugin.id

  local key = kong.db.plugins:cache_key(name,
                                        cfg.route_id,
                                        cfg.service_id,
                                        cfg.consumer_id,
                                        cfg.consumer_group_id,
                                        ws_id)

  -- TODO: deprecate usage of __key__ as id of plugin
  if not cfg.__key__ then
    cfg.__key__ = key
    -- generate a unique sequence across workers
    -- with a seq 0, plugin server generates an unused random instance id
    local next_seq, err = ngx.shared.kong:incr("plugins_iterator:__seq__", 1, 0, 0)
    if err then
      next_seq = 0
    end
    cfg.__seq__ = next_seq
  end

  return cfg
end


---
-- Lookup a configuration for a given combination of route_id, service_id, consumer_id, and consumer_group_id.
--
-- The function checks various combinations of route_id, service_id, consumer_id, and consumer_group_id to find
-- the best matching configuration in the given 'combos' table. The priority order is as follows:
--
-- 1. Consumer, Route, Service
-- 2. Consumer Group, Service, Route
-- 3. Consumer, Route
-- 4. Consumer, Service
-- 5. Consumer Group, Route
-- 6. Consumer Group, Service
-- 7. Route, Service
-- 8. Consumer
-- 9. Consumer Group
-- 10. Route
-- 11. Service
-- 12. Global
--
-- @function lookup_cfg
-- @tparam table combos A table containing configuration data indexed by compound keys.
-- @tparam string|nil route_id The route identifier.
-- @tparam string|nil service_id The service identifier.
-- @tparam string|nil consumer_id The consumer identifier.
-- @tparam string|nil consumer_groups The consumer group identifiers.
-- @return any|nil The configuration corresponding to the best matching combination, or 'nil' if no configuration is found.
local function lookup_cfg(combos, route_id, service_id, consumer_id, consumer_groups)
  -- Use the build_compound_key function to create an index for the 'combos' table
  if route_id and service_id and consumer_id then
    local key = build_compound_key(route_id, service_id, consumer_id, nil)
    if combos[key] then
      return combos[key]
    end
  end

  if route_id and service_id and consumer_groups then
    for _, consumer_group in ipairs(consumer_groups) do
      local key = build_compound_key(route_id, service_id, nil, consumer_group.id)
      if combos[key] then
        return combos[key]
      end
    end
  end

  if route_id and consumer_id then
    local key = build_compound_key(route_id, nil, consumer_id, nil)
    if combos[key] then
      return combos[key]
    end
  end

  if service_id and consumer_id then
    local key = build_compound_key(nil, service_id, consumer_id, nil)
    if combos[key] then
      return combos[key]
    end
  end

  if route_id and consumer_groups then
    for _, consumer_group in ipairs(consumer_groups) do
      local key = build_compound_key(route_id, nil, nil, consumer_group.id)
      if combos[key] then
        return combos[key]
      end
    end
  end

  if service_id and consumer_groups then
    for _, consumer_group in ipairs(consumer_groups) do
      local key = build_compound_key(nil, service_id, nil, consumer_group.id)
      if combos[key] then
        return combos[key]
      end
    end
  end

  if route_id and service_id then
    local key = build_compound_key(route_id, service_id, nil, nil)
    if combos[key] then
      return combos[key]
    end
  end

  if consumer_id then
    local key = build_compound_key(nil, nil, consumer_id, nil)
    if combos[key] then
      return combos[key]
    end
  end

  if consumer_groups then
    for _, consumer_group in ipairs(consumer_groups) do
      local key = build_compound_key(nil, nil, nil, consumer_group.id)
      if combos[key] then
        return combos[key]
      end
    end
  end

  if route_id then
    local key = build_compound_key(route_id, nil, nil, nil)
    if combos[key] then
      return combos[key]
    end
  end

  if service_id then
    local key = build_compound_key(nil, service_id, nil, nil)
    if combos[key] then
      return combos[key]
    end
  end

  return combos[PLUGIN_GLOBAL_KEY]
end


---
-- Load the plugin configuration based on the context (route, service, and consumer) and plugin handler rules.
--
-- This function filters out route, service, and consumer information from the context based on the plugin handler rules,
-- and then calls the 'lookup_cfg' function to get the best matching plugin configuration for the given combination of
-- route_id, service_id, and consumer_id.
--
-- @function load_configuration_through_combos
-- @tparam table ctx A table containing the context information, including route, service, and authenticated_consumer.
-- @tparam table combos A table containing configuration data indexed by compound keys.
-- @tparam table plugin A table containing plugin information, including the handler with no_route, no_service, and no_consumer rules.
-- @treturn any|nil The configuration corresponding to the best matching combination, or 'nil' if no configuration is found.
local function load_configuration_through_combos(ctx, combos, plugin)
  -- Filter out route, service, and consumer based on the plugin handler rules and get their ids
  local handler = plugin.handler
  local route_id = (not handler.no_route and ctx.route) and ctx.route.id or nil
  local service_id = (not handler.no_service and ctx.service) and ctx.service.id or nil
  local consumer_id = (not handler.no_consumer and ctx.authenticated_consumer) and ctx.authenticated_consumer.id or nil
  -- EE only
  -- Check if we have an authenticated_consumer_group
  local consumer_groups = (not handler.no_consumer_group and ctx.authenticated_consumer_groups and
                           not isempty(ctx.authenticated_consumer_groups)) and ctx.authenticated_consumer_groups or nil
  -- EE only end

  -- Call the lookup_cfg function to get the best matching plugin configuration
  return lookup_cfg(combos, route_id, service_id, consumer_id, consumer_groups)
end


local function get_workspace(self, ctx)
  if not ctx then
    return self.ws[kong.default_workspace]
  end

  return self.ws[workspaces.get_workspace_id(ctx) or kong.default_workspace]
end


---
-- Check if plugins need dynamic reordering upon request by looking at `dynamic_plugin_ordering`
-- @return boolean value
local function plugins_need_reordering(self, ctx)
  local ws = get_workspace(self, ctx)
  if ws and ws.dynamic_plugin_ordering then
    return true
  end
  return false
end


---
-- Applies topological ordering according to their configuration.
-- @return table of sorted handler,config tuple
local function get_ordered_plugins(iterator, plugins, phase)
  local i = 0
  local plugins_hash
  local plugins_array = {}
  for _, plugin, configuration in iterator, plugins, 0 do
    i = i + 1
    if i == 1 then
      plugins_hash = {}
    end
    local entry = { plugin = plugin, config = configuration }
    -- index plugin by name to find them during graph building
    -- The order of a non-integer index based table is non-deterministic!
    plugins_hash[plugin.name] = entry
    -- maintain a integer indexed list and a string indexed list for easier access
    plugins_array[i] = entry
  end
  if i > 1 then
    local ordered_plugins, err = topsort_plugins(plugins_hash, plugins_array, phase)
    if err then
      kong.log.err("failed to topological sort plugins: ", err)
      return plugins_array, i
    end

    return ordered_plugins, i
  end

  return plugins_array, i
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

  return i, plugins[i - 1], plugins[i]
end


local function get_global_iterator(self, phase)
  local plugins = self.globals[phase]
  local count = plugins and plugins[0] or 0
  if count == 0 then
    return nil
  end

  -- only execute this once per request
  if phase == "certificate" or (phase == "rewrite" and var.https ~= "on") then
    local i = 2
    while i <= count do
      kong.vault.update(plugins[i])
      i = i + 2
    end
  end

  return get_next_global_or_collected_plugin, plugins
end


local function get_collected_iterator(self, phase, ctx)
  local plugins = ctx.plugins
  if plugins then
    plugins = plugins[phase]
    if not plugins or plugins[0] == 0 then
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
  -- Only pass combos for the plugin we're operating on
  local combos = ws.combos[name]
  if combos then
    cfg = load_configuration_through_combos(ctx, combos, plugin)
    if cfg then
      kong.vault.update(cfg)
      local handler = plugin.handler
      local collected = ctx.plugins
      local collecting_phase
      local downstream_phases
      local downstream_phases_count
      if collected.websocket then
        collecting_phase = WS_COLLECTING_PHASE
        downstream_phases = WS_DOWNSTREAM_PHASES
        downstream_phases_count = WS_DOWNSTREAM_PHASES_COUNT
      else
        collecting_phase = COLLECTING_PHASE
        downstream_phases = DOWNSTREAM_PHASES
        downstream_phases_count = DOWNSTREAM_PHASES_COUNT
      end
      for j = 1, downstream_phases_count do
        local phase = downstream_phases[j]
        if handler[phase] then
          local n = collected[phase][0] + 2
          collected[phase][0] = n
          collected[phase][n] = cfg
          collected[phase][n - 1] = plugin
          if phase == "response" and not ctx.buffered_proxying then
            ctx.buffered_proxying = true
          end
        end
      end

      if handler[collecting_phase] then
        return i, plugin, cfg
      end
    end
  end

  return get_next_and_collect(ctx, i)
end


local function get_next_ordered(plugins, i)
  local i = i + 1
  local plugin = plugins[i]
  if not plugin then
    return nil
  end

  -- Durability condition to account for a case where the topsort algorithm adds a empty string
  if plugin == "" then
    return get_next_ordered(plugins, i)
  end

  if plugin then
    return i, plugin.plugin, plugin.config
  end

  return get_next_ordered(plugins, i)
end


local function get_priority_ordered_iterator(self, phase, ctx)
  local ws = get_workspace(self, ctx)
  ctx.plugins = get_table_for_ctx(ws, phase == WS_COLLECTING_PHASE)
  if not ws then
    return nil
  end

  local plugins = ws.plugins
  if plugins[0] == 0 then
    return nil
  end

  return get_next_and_collect, ctx
end


local function get_database_ordered_iterator(self, phase, ctx)
  local iterator, plugins = get_priority_ordered_iterator(self, phase, ctx)
  if not iterator then
    return nil
  end

  local ordered_plugins, count = get_ordered_plugins(iterator, plugins, phase)
  if count == 0 then
    return nil
  end

  return get_next_ordered, ordered_plugins
end


local function get_collecting_iterator(self, phase, ctx)
  if phase == "access" and plugins_need_reordering(self, ctx) then
    return get_database_ordered_iterator(self, phase, ctx)
  end

  return get_priority_ordered_iterator(self, phase, ctx)
end


local function new_ws_data()
  return {
    plugins = { [0] = 0 },
    combos = {},
  }
end


local function configure(configurable, ctx)
  ctx = ctx or ngx.ctx
  local kong_global = require "kong.global"
  for _, plugin in ipairs(CONFIGURABLE_PLUGINS) do
    local name = plugin.name

    kong_global.set_namespaced_log(kong, plugin.name, ctx)
    local start = utils.get_updated_monotonic_ms()
    local ok, err = pcall(plugin.handler[CONFIGURE_PHASE], plugin.handler, configurable[name])
    local elapsed = utils.get_updated_monotonic_ms() - start
    kong_global.reset_log(kong, ctx)

    if not ok then
      kong.log.err("failed to execute plugin '", name, ":", CONFIGURE_PHASE, " (", err, ")")
    else
      if elapsed > 50 then
        kong.log.notice("executing plugin '", name, ":", CONFIGURE_PHASE, " took excessively long: ", elapsed, " ms")
      end
    end
  end
end


local function create_configure(configurable)
  -- we only want the plugin_iterator:configure to be only available on proxying
  -- nodes (or data planes), thus we disable it if this code gets executed on control
  -- plane or on a node that does not listen any proxy ports.
  --
  -- TODO: move to PDK, e.g. kong.node.is_proxying()
  if kong.configuration.role == "control_plane"
  or ((subsystem == "http"   and #kong.configuration.proxy_listeners == 0) or
      (subsystem == "stream" and #kong.configuration.stream_listeners == 0))
  then
    return function() end
  end

  return function(self, ctx)
    configure(configurable, ctx)
    -- self destruct the function so that it cannot be called twice
    -- if it ever happens to be called twice, it should be very visible
    -- because of this.
    self.configure = nil
    configurable = nil
  end
end


function PluginsIterator.new(version)
  local is_not_dbless = kong.db.strategy ~= "off"
  if is_not_dbless then
    if not version then
      error("version must be given", 2)
    end
  end

  LOADED_PLUGINS = LOADED_PLUGINS or get_loaded_plugins()
  CONFIGURABLE_PLUGINS = CONFIGURABLE_PLUGINS or get_configurable_plugins()
  ENABLED_PLUGINS = ENABLED_PLUGINS or kong.configuration.loaded_plugins

  local ws_id = workspaces.get_workspace_id() or kong.default_workspace
  local ws = {
    [ws_id] = new_ws_data()
  }

  local counter = 0
  local globals
  do
    globals = {}
    for _, phase in ipairs(NON_COLLECTING_PHASES) do
      globals[phase] = { [0] = 0 }
    end
  end

  local configurable = {}
  local has_plugins = false

  local page_size = kong.db.plugins.pagination.max_page_size
  for plugin, err in kong.db.plugins:each(page_size, GLOBAL_QUERY_OPTS) do
    if err then
      return nil, err
    end

    local name = plugin.name
    if not ENABLED_PLUGINS[name] then
      return nil, name .. " plugin is in use but not enabled"
    end

    if is_not_dbless and counter > 0 and counter % page_size == 0 and kong.core_cache then
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
      -- Get the plugin configuration for the specified workspace (ws_id)
      local cfg = get_plugin_config(plugin, name, plugin.ws_id)
      if cfg then
        has_plugins = true

        if CONFIGURABLE_PLUGINS[name] then
          configurable[name] = configurable[name] or {}
          configurable[name][#configurable[name] + 1] = cfg
        end

        local data = ws[plugin.ws_id]
        if not data then
          data = new_ws_data()
          ws[plugin.ws_id] = data
        end

        -- Flag the workspace with `dynamic_plugin_ordering` this signals that we have to sort plugins differently
        -- based on the request.
        if plugin.ordering then
          data.dynamic_plugin_ordering = true
          kong.log.info("Changing the order of plugins in this workspace dynamically")
        end

        local plugins = data.plugins
        local combos = data.combos

        plugins[name] = true

        -- Retrieve route_id, service_id, and consumer_id from the plugin object, if they exist
        local route_id = plugin.route and plugin.route.id
        local service_id = plugin.service and plugin.service.id
        local consumer_id = plugin.consumer and plugin.consumer.id
        -- EE only
        local consumer_group_id  = plugin.consumer_group and plugin.consumer_group.id

        -- Determine if the plugin configuration is global (i.e., not tied to any route, service, consumer or group)
        if not (route_id or service_id or consumer_id or consumer_group_id) and plugin.ws_id == kong.default_workspace then
          -- Store the global configuration for the plugin in the 'globals' table
          globals[name] = cfg
        end

        -- Initialize an empty table for the plugin in the 'combos' table if it doesn't already exist
        combos[name] = combos[name] or {}

        -- Build a compound key using the route_id, service_id, and consumer_id
        local compound_key = build_compound_key(route_id, service_id, consumer_id, consumer_group_id)

        -- Store the plugin configuration in the 'combos' table using the compound key
        combos[name][compound_key] = cfg
      end
    end

    counter = counter + 1
  end

  if has_plugins then
    -- loaded_plugins contains all the plugins that we _may_ execute
    for _, plugin in ipairs(LOADED_PLUGINS) do
      local name = plugin.name
      -- ws contains all the plugins that are associated to the request via route/service/global mappings
      for _, data in pairs(ws) do
        local plugins = data.plugins
        if plugins[name] then -- is the plugin associated to the request(workspace/route/service)?
          local n = plugins[0] + 1
          plugins[n] = plugin -- next item goes into next slot
          plugins[0] = n      -- index 0 holds table size
          plugins[name] = nil -- remove the placeholder value
        end
      end

      local cfg = globals[name]
      if cfg then
        for _, phase in ipairs(NON_COLLECTING_PHASES) do
          if plugin.handler[phase] then
            local plugins = globals[phase]
            local n = plugins[0] + 2
            plugins[0] = n
            plugins[n] = cfg
            plugins[n - 1] = plugin
          end
        end
      end
    end
  end

  return {
    version = version,
    ws = ws,
    loaded = LOADED_PLUGINS,
    configure = create_configure(configurable),
    globals = globals,
    get_init_worker_iterator = get_init_worker_iterator,
    get_global_iterator = get_global_iterator,
    get_collecting_iterator = get_collecting_iterator,
    get_collected_iterator = get_collected_iterator,
    has_plugins = has_plugins,
    release = release,
  }
end


-- for testing
PluginsIterator.lookup_cfg = lookup_cfg
PluginsIterator.build_compound_key = build_compound_key


return PluginsIterator
