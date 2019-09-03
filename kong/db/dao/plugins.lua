local constants = require "kong.constants"
local utils = require "kong.tools.utils"
local DAO = require "kong.db.dao"
local wokspaces = require "kong.workspaces"
local tracing = require "kong.tracing"
local plugin_loader = require "kong.db.schema.plugin_loader"
local BasePlugin = require "kong.plugins.base_plugin"


local Plugins = {}


local fmt = string.format
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
  end

  if type(plugin.service) == "table" then
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


local function sort_by_handler_priority(a, b)
  return (a.handler.PRIORITY or 0) > (b.handler.PRIORITY or 0)
end


function Plugins:insert(entity, options)
  local ok, err, err_t = check_protocols_match(self, entity)
  if not ok then
    return nil, err, err_t
  end
  return self.super.insert(self, entity, options)
end


function Plugins:update(primary_key, entity, options)
  local rbw_entity = self.super.select(self, primary_key, options) -- ignore errors
  if rbw_entity then
    entity = self.schema:merge_values(entity, rbw_entity)
  end
  local ok, err, err_t = check_protocols_match(self, entity)
  if not ok then
    return nil, err, err_t
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

--- Given a set of plugin names, check if all plugins stored
-- in the database fall into this set.
-- @param plugin_set a set of plugin names.
-- @return true or nil and an error message.
function Plugins:check_db_against_config(plugin_set)
  local in_db_plugins = {}
  ngx_log(ngx_DEBUG, "Discovering used plugins")

  for row, err in self:each(1000) do
    if err then
      return nil, tostring(err)
    end
    in_db_plugins[row.name] = true
  end

  -- check all plugins in DB are enabled/installed
  for plugin in pairs(in_db_plugins) do
    if not plugin_set[plugin] then
      return nil, plugin .. " plugin is in use but not enabled"
    end
  end

  return true
end


local function load_plugin_handler(plugin)
    -- NOTE: no version _G.kong (nor PDK) in plugins main chunk

    local plugin_handler = "kong.plugins." .. plugin .. ".handler"


    local ok, handler = utils.load_module_if_exists(plugin_handler)
    if not ok then
      return nil, plugin .. " plugin is enabled but not installed;\n" .. plugin_handler
    end

    tracing.plugin_wrap(handler, plugin)
    return handler
end


local function load_plugin_entity_strategy(schema, db, plugin)
        local Strategy = require(fmt("kong.db.strategies.%s", db.strategy))
            local strategy, err = Strategy.new(db.connector, schema, db.errors)
            if not strategy then
              return nil, err
            end

  local custom_strat = fmt("kong.plugins.%s.strategies.%s.%s",
                           plugin, db.strategy, schema.name)
  local exists, mod = utils.load_module_if_exists(custom_strat)
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
  -- XXX EE: maybe schema_def comming from plugin_entity_loader?
  if schema.workspaceable then
    local unique_keys = {}
    for field_name, field_schema in schema:each_field() do
      if field_schema.unique then
        unique_keys[field_name] = field_schema
      end
    end
    wokspaces.register_workspaceable_relation(schema.name, schema.primary_key, unique_keys)
  end
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

  if schema.fields.consumer and schema.fields.consumer.eq == null then
    plugin.no_consumer = true
  end
  if schema.fields.route and schema.fields.route.eq == null then
    plugin.no_route = true
  end
  if schema.fields.service and schema.fields.service.eq == null then
    plugin.no_service = true
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

  local handlers = {}
  local errs

  -- load installed plugins
  for plugin in pairs(plugin_set) do
    local handler, err = load_plugin(self, plugin)

    if handler then
      if type(handler.is) == "function" and handler:is(BasePlugin) then
        -- Backwards-compatibility for 0.x and 1.x plugins inheriting from the
        -- BasePlugin class.
        -- TODO: deprecate & remove
        handler = handler()
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

  self.handlers = handlers

  return true
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


function Plugins:select_by_cache_key(key, options)
  local schema_state = assert(self.db:last_schema_state())

  -- if migration is complete, disable this translator function
  -- and use the regular function
  if schema_state:is_migration_executed("core", "001_14_to_15") then
    self.select_by_cache_key = self.super.select_by_cache_key
    Plugins.select_by_cache_key = nil
    return self.super.select_by_cache_key(self, key, options)
  end

  -- first try new way
  local entity, new_err = self.super.select_by_cache_key(self, key, options)

  if not new_err then -- the step above didn't fail
    -- we still need to check whether the migration is done,
    -- because the new table may be only partially full
    local schema_state = assert(self.db:schema_state())

    -- if migration is complete, disable this translator function and return
    if schema_state:is_migration_executed("core", "001_14_to_15") then
      self.select_by_cache_key = self.super.select_by_cache_key
      Plugins.select_by_cache_key = nil
      return entity
    end
  end

  -- otherwise, we either have not started migrating, or we're migrating but
  -- the plugin identified by key doesn't have a cache_key yet
  -- do things "the old way" in both cases
  local row, old_err = self.strategy:select_by_cache_key_migrating(key)
  if row then
    return self:row_to_entity(row, {include_ws = true})
  end

  -- when both ways have failed, return the "new" error message.
  -- otherwise, return whichever error is not-nil
  local err = (new_err and old_err) and new_err or old_err

  return nil, err
end


return Plugins
