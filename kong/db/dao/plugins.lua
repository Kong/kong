-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require "kong.constants"
local DAO = require "kong.db.dao"
local plugin_loader = require "kong.db.schema.plugin_loader"
local reports = require "kong.reports"
local plugin_servers = require "kong.runloop.plugin_servers"
local cjson = require "cjson"
local wasm_plugins = require "kong.runloop.wasm.plugins"

-- XXX EE
local hooks = require "kong.hooks"


local clone = require "table.clone"
local version = require "version"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists


local Plugins = {}


local fmt = string.format
local type = type
local null = ngx.null
local pairs = pairs
local ipairs = ipairs
local concat = table.concat
local insert = table.insert
local tostring = tostring
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG
local ngx_get_phase = ngx.get_phase


local GLOBAL_QUERY_OPTS = { workspace = null, show_ws_id = true }


local function has_a_common_protocol_with_route(plugin, route)
  local plugin_prot = plugin.protocols
  local route_prot = route.protocols
  -- plugin.protocols and route.protocols are both sets provided by the schema
  -- this means that they can be iterated as over an array, and queried as a hash
  for i = 1, #plugin_prot do
    if route_prot[plugin_prot[i]] then
      return true
    end
  end
end


local function has_common_protocol_with_service(self, plugin, service_pk)
  local had_at_least_one_route = false
  for route, err, err_t in self.db.routes:each_for_service(service_pk) do
    if not route then
      return nil, err, err_t
    end

    had_at_least_one_route = true

    if has_a_common_protocol_with_route(plugin, route) then
      return true
    end
  end

  return not had_at_least_one_route
end


local function check_protocols_match(self, plugin)
  if type(plugin.protocols) ~= "table" then
    return true
  end

  if type(plugin.route) == "table" then
    local route = self.db.routes:select(plugin.route) -- ignore error
    if route and not has_a_common_protocol_with_route(plugin, route) then
      local err_t = self.errors:schema_violation({
        protocols = "must match the associated route's protocols",
      })
      return nil, tostring(err_t), err_t
    end

  elseif type(plugin.service) == "table" then
    if not has_common_protocol_with_service(self, plugin, plugin.service) then
      local err_t = self.errors:schema_violation({
        protocols = "must match the protocols of at least one route " ..
                    "pointing to this Plugin's service",
      })
      return nil, tostring(err_t), err_t
    end
  end

  return true
end


local function check_ordering_validity(self, entity)
  --[[
    Plugins that are scoped to a consumer can't be a target for reordering
    because they rely on a context (ngx.authenticated_consumer) which is only
    set during the access phase of an authentication plugin. This means that
    we can't influence the order of plugins without running their access phase
    first which is a catch-22.
  --]]
  if type(entity.ordering) ~= "table" then
    -- no reordering requested, no need to validate further
    return true
  end
  if entity.consumer == cjson.null then
    -- cjson null representation
    return true
  end
  if entity.consumer == nil then
    -- tests set explicit nil
    return true
  end
  -- all other cases should result in an error
  local err_t = self.errors:schema_violation({
    ordering = "can't apply dynamic reordering to consumer scoped plugins",
  })
  return nil, tostring(err_t), err_t
end

function Plugins:insert(entity, options)
  local ok, err, err_t = check_protocols_match(self, entity)
  if not ok then
    return nil, err, err_t
  end
  local ok_o, err_o, err_t_o = check_ordering_validity(self, entity)
  if not ok_o then
    return nil, err_o, err_t_o
  end
  return self.super.insert(self, entity, options)
end


function Plugins:update(primary_key, entity, options)
  local rbw_entity
  if entity.protocols or entity.service or entity.route then
    if (entity.protocols and not entity.route)
    or (entity.service and not entity.protocols)
    or (entity.route and not entity.protocols)
    then
      rbw_entity = self.super.select(self, primary_key, options)
      if rbw_entity then
        entity.protocols = entity.protocols or rbw_entity.protocols
        entity.service = entity.service or rbw_entity.service
        entity.route = entity.route or rbw_entity.route
      end
      rbw_entity = rbw_entity or {}
    end
    local ok, err, err_t = check_protocols_match(self, entity)
    if not ok then
      return nil, err, err_t
    end
  end
  if entity.ordering or entity.consumer then
    if not (rbw_entity or (entity.ordering and entity.consumer)) then
      rbw_entity = self.super.select(self, primary_key, options) or {}
    end

    entity.ordering = entity.ordering or rbw_entity.ordering
    entity.consumer = entity.consumer or rbw_entity.consumer

    local ok_o, err_o, err_t_o = check_ordering_validity(self, entity)
    if not ok_o then
      return nil, err_o, err_t_o
    end
  end
  return self.super.update(self, primary_key, entity, options)
end


function Plugins:upsert(primary_key, entity, options)
  local ok, err, err_t = check_protocols_match(self, entity)
  if not ok then
    return nil, err, err_t
  end
  local ok_o, err_o, err_t_o = check_ordering_validity(self, entity)
  if not ok_o then
    return nil, err_o, err_t_o
  end
  return self.super.upsert(self, primary_key, entity, options)
end


local function implements(plugin, method)
  if type(plugin) ~= "table" then
    return false
  end

  local m = plugin[method]
  return type(m) == "function"
end


local function validate_priority(prio)
  if type(prio) ~= "number" or
          prio ~= prio or  -- NaN
          math.abs(prio) == math.huge or
          math.floor(prio) ~= prio then
    return false
  end
  return true
end


-- Returns the cleaned version string, only x.y.z part
local function validate_version(v)
  if type(v) ~= "string" then
    return false
  end
  local vparsed = version(v)
  if not vparsed or vparsed[4] ~= nil then
    return false
  end

  return tostring(vparsed)
end


local load_plugin_handler, load_custom_plugin_handler do
  local function validate_handler(name, handler, err_title)
    if type(handler) == "table" then
      if not validate_priority(handler.PRIORITY) then
        return nil, fmt(
          "%s %q cannot be loaded because its PRIORITY field is not " ..
          "a valid integer number, got: %q.\n", err_title, name, tostring(handler.PRIORITY))
      end

      local v = validate_version(handler.VERSION)
      if v then
        handler.VERSION = v -- update to cleaned version string
      else
        return nil, fmt(
          "%s %q cannot be loaded because its VERSION field does not " ..
          "follow the \"x.y.z\" format, got: %q.\n", err_title, name, tostring(handler.VERSION))
      end
    end

    if implements(handler, "response") and (implements(handler, "header_filter") or
                                            implements(handler, "body_filter"))
    then
      return nil, fmt(
        "%s %q can't be loaded because it implements both `response` " ..
        "and `header_filter` or `body_filter` methods.\n", err_title, name)
    end

    return true
  end

  function load_plugin_handler(name)
    -- NOTE: no version _G.kong (nor PDK) in plugins main chunk

    local plugin_handler = "kong.plugins." .. name .. ".handler"
    local ok, handler = load_module_if_exists(plugin_handler)
    if not ok then
      ok, handler = wasm_plugins.load_plugin(name)
      if type(handler) == "table" then
        handler._wasm = true
      end
    end

    if not ok then
      ok, handler = plugin_servers.load_plugin(name)
      if type(handler) == "table" then
        handler._go = true
      end
    end

    if not ok then
      return nil, name .. " plugin is enabled but not installed;\n" .. handler
    end

    local ok, err = validate_handler(name, handler, "Plugin")
    if not ok then
      return nil, err
    end

    return handler
  end

  local sandbox = require("kong.tools.sandbox").sandbox_handler
  local pcall = pcall
  function load_custom_plugin_handler(plugin)
    local name = plugin.name
    local chunk = plugin.handler
    if type(chunk) == "table" then
      return chunk
    end

    local ok, compiled = pcall(sandbox, chunk, name)
    if not ok then
      return nil, fmt("compiling custom '%s' plugin handler failed: %s", name, compiled)
    end

    local ok, handler = pcall(compiled)
    if not ok then
      return nil, fmt("loading custom '%s' plugin handler failed: %s", name, handler)
    end

    local ok, err = validate_handler(name, handler, "Custom plugin")
    if not ok then
      return nil, err
    end

    if implements(handler, "init_worker") then
      return nil, "Custom plugin %q can't be loaded because it implements `init_worker`."
    end

    return handler
  end
end


local function load_plugin_entity_strategy(schema, db, name)
  local Strategy = require(fmt("kong.db.strategies.%s", db.strategy))
  local strategy, err = Strategy.new(db.connector, schema, db.errors)
  if not strategy then
    return nil, err
  end

  local custom_strat = fmt("kong.plugins.%s.strategies.%s.%s",
                           name, db.strategy, schema.name)
  local exists, mod = load_module_if_exists(custom_strat)
  if exists and mod then
    local parent_mt = getmetatable(strategy)
    local mt = {
      __index = function(_, k)
        -- explicit parent
        if k == "super" then
          return parent_mt
        end

        -- override
        local f = mod[k]
        if f then
          return f
        end

        -- parent fallback
        return parent_mt[k]
      end
    }

    setmetatable(strategy, mt)
  end

  db.strategies[schema.name] = strategy

  local dao, err = DAO.new(db, schema, strategy, db.errors)
  if not dao then
    return nil, err
  end
  db.daos[schema.name] = dao
end


local function plugin_entity_loader(db)
  return function(name, definition)
    ngx_log(ngx_DEBUG, fmt("Loading custom plugin entity: '%s.%s'", name, definition.name))
    local schema, err = plugin_loader.load_entity_schema(name, definition, db.errors)
    if not schema then
      return nil, err
    end

    load_plugin_entity_strategy(schema, db, name)
  end
end


local function patch_handler(definition, handler)
  for _, field in ipairs(definition.fields) do
    if field.consumer and field.consumer.eq == null then
      handler.no_consumer = true
    end

    if field.consumer_group and field.consumer_group.eq == null then
      handler.no_consumer_group = true
    end

    if field.route and field.route.eq == null then
      handler.no_route = true
    end

    if field.service and field.service.eq == null then
      handler.no_service = true
    end
  end
end


local function load_plugin(self, name)
  if self.installed and self.installed[name] then
    return self.installed[name]
  end

  local db = self.db

  if constants.DEPRECATED_PLUGINS[name] then
    ngx_log(ngx_WARN, "plugin '", name, "' has been deprecated")
  end

  local handler, err = load_plugin_handler(name)
  if not handler then
    return nil, err
  end

  local definition, err = plugin_loader.load_subschema(self.schema, name, db.errors)
  if err then
    return nil, err
  end

  patch_handler(definition, handler)

  ngx_log(ngx_DEBUG, "Loading plugin: ", name)

  if db.strategy then -- skip during tests
    local _, err = plugin_loader.load_entities(name, db.errors,
                                               plugin_entity_loader(db))
    if err then
      return nil, err
    end
  end

  return handler
end


local function load_custom_plugin(self, plugin)
  local db = self.db

  local handler, err = load_custom_plugin_handler(plugin)
  if not handler then
    return nil, err
  end

  local definition, err, subschema = plugin_loader.load_custom_subschema(self.schema, plugin, db.errors)
  if err then
    return nil, err
  end

  patch_handler(definition, handler)

  ngx_log(ngx_DEBUG, "Loading custom plugin: ", plugin.name)

  return handler, nil, definition, subschema
end


local function should_reload_custom_plugins()
  if ngx.IS_CLI then
    return false -- no reload on CLI (as it potentially slows down the startup)
  end

  if not kong.configuration.custom_plugins_enabled then
    return false -- no reload on when the feature is not enabled
  end

  if kong.configuration.database == "off" and ngx_get_phase() == "init" then
    return false -- no reload on dbless in init as lmdb cannot be accessed
  end

  return true
end


--- Load subschemas for all configured plugins into the Plugins entity. It has two side effects:
--  * It makes the Plugin sub-schemas available for the rest of the application
--  * It initializes the Plugin.
-- @param plugin_set a set of plugin names.
-- @return true if success, or nil and an error message.
function Plugins:load_plugin_schemas(plugin_set)
  local reload_custom_plugins = should_reload_custom_plugins()

  -- Normal plugins (stored in fs) are reloaded by passing a `plugin_set`.
  -- Custom plugins (stored in db) are reloaded without passing a `plugin_set`.
  if not plugin_set and not reload_custom_plugins then
    -- no `plugin_set` was provided and custom plugins are not to be reloaded, we can skip it.
    return true
  end

  local go_plugins_cnt = 0
  local installed
  local handlers
  local errs

  if plugin_set then
    installed = {}
    for name in pairs(plugin_set) do
      local handler, err = load_plugin(self, name)
      if handler then
        if handler._go then
          go_plugins_cnt = go_plugins_cnt + 1
        end
        installed[name] = handler

      else
        errs = errs or {}
        insert(errs, "on plugin '" .. name .. "': " .. tostring(err))
      end
    end

    if errs then
      return nil, "error loading plugin schemas: " .. concat(errs, "; ")
    end

  else
    installed = self.installed or {}
  end

  if reload_custom_plugins then
    local custom_plugins
    local page_size = self.db.custom_plugins.pagination.max_page_size
    for plugin, err in self.db.custom_plugins:each(page_size, GLOBAL_QUERY_OPTS) do
      if err then
        errs = errs or {}
        insert(errs, "on custom plugins: " .. tostring(err))
        break
      end

      local name = plugin.name
      if installed[name] then
        errs = errs or {}
        insert(errs, "on custom plugin '" .. name .. "': " .. "name conflicts with loaded plugins")

      else
        local handler, err, definition, subschema = load_custom_plugin(self, plugin)
        if handler then
          custom_plugins = custom_plugins or {}
          insert(custom_plugins, { name, handler, definition, subschema })

        else
          errs = errs or {}
          insert(errs, "on custom plugin '" .. plugin.name .. "': " .. tostring(err))
        end
      end
    end

    if errs then
      return nil, "error loading custom plugin schemas: " .. concat(errs, "; ")
    end

    if custom_plugins then
      handlers = clone(installed)
      for _, custom_plugin in ipairs(custom_plugins) do
        local name = custom_plugin[1]
        local handler = custom_plugin[2]
        local definition = custom_plugin[3]
        local subschema = custom_plugin[4]

        plugin_loader.reset_custom_subschema(self.schema, name, definition, subschema)
        handlers[name] = handler
      end
    end

    self.schema:unload_subschemas(handlers or installed)
  end

  if not self.installed then
    reports.add_immutable_value("go_plugins_cnt", go_plugins_cnt)
  end

  -- XXX EE
  assert(hooks.run_hook("dao:plugins:load", handlers or installed))

  self.installed = installed
  self.handlers = handlers or installed

  return true
end


---
-- Sort by handler priority and check for collisions. In case of a collision
-- sorting will be applied based on the plugin's name.
-- @tparam table plugin table containing `handler` table and a `name` string
-- @tparam table plugin table containing `handler` table and a `name` string
-- @treturn boolean outcome of sorting
local sort_by_handler_priority = function (a, b)
  local prio_a = a.handler.PRIORITY or 0
  local prio_b = b.handler.PRIORITY or 0
  if prio_a == prio_b and not
      (prio_a == 0 or prio_b == 0) then
    return a.name > b.name
  end
  return prio_a > prio_b
end

Plugins.sort_by_handler_priority = sort_by_handler_priority
Plugins.implements = implements
Plugins.validate_version = validate_version
Plugins.validate_priority = validate_priority


local function get_handlers_from(handlers)
  local list = {}
  local len = 0
  for name, handler in pairs(handlers) do
    len = len + 1
    list[len] = { name = name, handler = handler }
  end

  table.sort(list, sort_by_handler_priority)

  return list
end


-- Requires Plugins:load_plugin_schemas to be loaded first
-- @return an array where each element has the format { name = "keyauth", handler = function() .. end }. Or nil, error
function Plugins:get_handlers()
  if not self.handlers then
    return nil, "Please invoke Plugins:load_plugin_schemas() before invoking Plugins:get_handlers"
  end

  return get_handlers_from(self.handlers)
end


-- Requires Plugins:load_plugin_schemas to be loaded first
-- @return an array where each element has the format { name = "keyauth", handler = function() .. end }. Or nil, error
function Plugins:get_installed_handlers()
  if not self.installed then
    return nil, "Please invoke Plugins:load_plugin_schemas() before invoking Plugins:get_installed_handlers"
  end

  return get_handlers_from(self.installed)
end


-- @ca_id: the id of ca certificate to be searched
-- @limit: the maximum number of entities to return (must >= 0)
-- @plugin_names: the plugin names to filter the entities (must be of type table, string or nil)
-- @return an array of the plugin entity
function Plugins:select_by_ca_certificate(ca_id, limit, plugin_names)
  local param_type = type(plugin_names)
  if param_type ~= "table" and param_type ~= "string" and param_type ~= "nil" then
    return nil, "parameter `plugin_names` must be of type table, string, or nil"
  end

  local plugins, err = self.strategy:select_by_ca_certificate(ca_id, limit, plugin_names)
  if err then
    return nil, err
  end

  return self:rows_to_entities(plugins), nil
end


return Plugins
