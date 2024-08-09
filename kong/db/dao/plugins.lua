local constants = require "kong.constants"
local DAO = require "kong.db.dao"
local plugin_loader = require "kong.db.schema.plugin_loader"
local reports = require "kong.reports"
local plugin_servers = require "kong.runloop.plugin_servers"
local version = require "version"
local load_module_if_exists = require "kong.tools.module".load_module_if_exists


local Plugins = {}


local fmt = string.format
local type = type
local null = ngx.null
local pairs = pairs
local tostring = tostring
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG



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

function Plugins:insert(entity, options)
  local ok, err, err_t = check_protocols_match(self, entity)
  if not ok then
    return nil, err, err_t
  end
  return self.super.insert(self, entity, options)
end


function Plugins:update(primary_key, entity, options)
  if entity.protocols or entity.service or entity.route then
    if (entity.protocols and not entity.route)
    or (entity.service and not entity.protocols)
    or (entity.route and not entity.protocols)
    then
      local rbw_entity = self.super.select(self, primary_key, options)
      if rbw_entity then
        entity.protocols = entity.protocols or rbw_entity.protocols
        entity.service = entity.service or rbw_entity.service
        entity.route = entity.route or rbw_entity.route
      end
    end
    local ok, err, err_t = check_protocols_match(self, entity)
    if not ok then
      return nil, err, err_t
    end
  end
  return self.super.update(self, primary_key, entity, options)
end


function Plugins:upsert(primary_key, entity, options)
  local ok, err, err_t = check_protocols_match(self, entity)
  if not ok then
    return nil, err, err_t
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


local load_plugin_handler do

  local function valid_priority(prio)
    if type(prio) ~= "number" or
       prio ~= prio or  -- NaN
       math.abs(prio) == math.huge or
       math.floor(prio) ~= prio then
      return false
    end
    return true
  end

  -- Returns the cleaned version string, only x.y.z part
  local function valid_version(v)
    if type(v) ~= "string" then
      return false
    end
    local vparsed = version(v)
    if not vparsed or vparsed[4] ~= nil then
      return false
    end

    return tostring(vparsed)
  end


  function load_plugin_handler(plugin)
    -- NOTE: no version _G.kong (nor PDK) in plugins main chunk

    local plugin_handler = "kong.plugins." .. plugin .. ".handler"
    local ok, handler = load_module_if_exists(plugin_handler)
    if not ok then
      ok, handler = plugin_servers.load_plugin(plugin)
      if type(handler) == "table" then
        handler._go = true
      end
    end

    if not ok then
      return nil, plugin .. " plugin is enabled but not installed;\n" .. handler
    end

    if type(handler) == "table" then

      if not valid_priority(handler.PRIORITY) then
        return nil, fmt(
          "Plugin %q cannot be loaded because its PRIORITY field is not " ..
          "a valid integer number, got: %q.\n", plugin, tostring(handler.PRIORITY))
      end

      local v = valid_version(handler.VERSION)
      if v then
        handler.VERSION = v -- update to cleaned version string
      else
        return nil, fmt(
          "Plugin %q cannot be loaded because its VERSION field does not " ..
          "follow the \"x.y.z\" format, got: %q.\n", plugin, tostring(handler.VERSION))
      end
    end

    if implements(handler, "response") and
        (implements(handler, "header_filter") or implements(handler, "body_filter"))
    then
      return nil, fmt(
        "Plugin %q can't be loaded because it implements both `response` " ..
        "and `header_filter` or `body_filter` methods.\n", plugin)
    end

    return handler
  end
end


local function load_plugin_entity_strategy(schema, db, plugin)
  local Strategy = require(fmt("kong.db.strategies.%s", db.strategy))
  local strategy, err = Strategy.new(db.connector, schema, db.errors)
  if not strategy then
    return nil, err
  end

  local custom_strat = fmt("kong.plugins.%s.strategies.%s.%s",
                           plugin, db.strategy, schema.name)
  local exists, mod = load_module_if_exists(custom_strat)
  if exists and mod then
    local parent_mt = getmetatable(strategy)
    local mt = {
      __index = function(t, k)
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
  return function(plugin, schema_def)
    ngx_log(ngx_DEBUG, fmt("Loading custom plugin entity: '%s.%s'", plugin, schema_def.name))
    local schema, err = plugin_loader.load_entity_schema(plugin, schema_def, db.errors)
    if not schema then
      return nil, err
    end

    load_plugin_entity_strategy(schema, db, plugin)
  end
end


local function load_plugin(self, plugin)
  local db = self.db

  if constants.DEPRECATED_PLUGINS[plugin] then
    ngx_log(ngx_WARN, "plugin '", plugin, "' has been deprecated")
  end

  local handler, err = load_plugin_handler(plugin)
  if not handler then
    return nil, err
  end

  local schema, err = plugin_loader.load_subschema(self.schema, plugin, db.errors)
  if err then
    return nil, err
  end

  for _, field in ipairs(schema.fields) do
    if field.consumer and field.consumer.eq == null then
      handler.no_consumer = true
    end

    if field.route and field.route.eq == null then
      handler.no_route = true
    end

    if field.service and field.service.eq == null then
      handler.no_service = true
    end
  end

  ngx_log(ngx_DEBUG, "Loading plugin: ", plugin)

  if db.strategy then -- skip during tests
    local _, err = plugin_loader.load_entities(plugin, db.errors,
                                               plugin_entity_loader(db))
    if err then
      return nil, err
    end
  end

  return handler
end


--- Load subschemas for all configured plugins into the Plugins entity. It has two side effects:
--  * It makes the Plugin sub-schemas available for the rest of the application
--  * It initializes the Plugin.
-- @param plugin_set a set of plugin names.
-- @return true if success, or nil and an error message.
function Plugins:load_plugin_schemas(plugin_set)
  self.handlers = nil

  local go_plugins_cnt = 0
  local handlers = {}
  local errs

  -- load installed plugins
  for plugin in pairs(plugin_set) do
    local handler, err = load_plugin(self, plugin)

    if handler then
      if handler._go then
        go_plugins_cnt = go_plugins_cnt + 1
      end

      handlers[plugin] = handler

    else
      errs = errs or {}
      table.insert(errs, "on plugin '" .. plugin .. "': " .. tostring(err))
    end
  end

  if errs then
    return nil, "error loading plugin schemas: " .. table.concat(errs, "; ")
  end

  reports.add_immutable_value("go_plugins_cnt", go_plugins_cnt)

  self.handlers = handlers

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


-- Requires Plugins:load_plugin_schemas to be loaded first
-- @return an array where each element has the format { name = "keyauth", handler = function() .. end }. Or nil, error
function Plugins:get_handlers()
  if not self.handlers then
    return nil, "Please invoke Plugins:load_plugin_schemas() before invoking Plugins:get_plugin_handlers"
  end

  local list = {}
  local len = 0
  for name, handler in pairs(self.handlers) do
    len = len + 1
    list[len] = { name = name, handler = handler }
  end

  table.sort(list, sort_by_handler_priority)

  return list
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
