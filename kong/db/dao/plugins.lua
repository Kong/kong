local constants = require "kong.constants"
local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"
local Entity = require "kong.db.schema.entity"
local DAO = require "kong.db.dao"
local MetaSchema = require "kong.db.schema.metaschema"


local Plugins = {}


local fmt = string.format
local null = ngx.null
local type = type
local next = next
local pairs = pairs
local ipairs = ipairs
local insert = table.insert
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


function Plugins:insert(entity, options)
  local ok, err, err_t = check_protocols_match(self, entity)
  if not ok then
    return nil, err, err_t
  end
  return self.super.insert(self, entity, options)
end


function Plugins:update(primary_key, entity, options)
  local rbw_entity = self.strategy:select(primary_key, options) -- ignore errors
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
  local rbw_entity = self.strategy:select(primary_key, options) -- ignore errors
  if rbw_entity then
    entity = self.schema:merge_values(entity, rbw_entity)
  end
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


--- Check if a string is a parseable URL.
-- @param v input string string
-- @return boolean indicating whether string is an URL.
local function validate_url(v)
  if v and type(v) == "string" then
    local url = require("socket.url").parse(v)
    if url and not url.path then
      url.path = "/"
    end
    return not not (url and url.path and url.host and url.scheme)
  end
end


--- Read a plugin schema table in the old-DAO format and produce a
-- best-effort translation of it into a plugin subschema in the new-DAO format.
-- @param name a string with the schema name.
-- @param old_schema the old-format schema table.
-- @return a table with a new-format plugin subschema; or nil and a message.
local function convert_legacy_schema(name, old_schema)
  local new_schema = {
    name = name,
    fields = {
      config = {
        type = "record",
        required = true,
        fields = {}
      }
    },
    entity_checks = old_schema.entity_checks,
  }
  for old_fname, old_fdata in pairs(old_schema.fields) do
    local new_fdata = {}
    local new_field = { [old_fname] = new_fdata }
    local elements = {}
    for k, v in pairs(old_fdata) do

      if k == "type" then
        if v == "url" then
          new_fdata.type = "string"
          new_fdata.custom_validator = validate_url

        elseif v == "table" then
          if old_fdata.schema and old_fdata.schema.flexible then
            new_fdata.type = "map"
          else
            new_fdata.type = "record"
            new_fdata.required = true
          end

        elseif v == "array" then
          new_fdata.type = "array"
          elements.type = "string"
          -- FIXME stored as JSON in old db

        elseif v == "timestamp" then
          new_fdata = typedefs.timestamp

        elseif v == "string" then
          new_fdata.type = v
          new_fdata.len_min = 0

        elseif v == "number"
            or v == "boolean" then
          new_fdata.type = v

        else
          return nil, "unkown legacy field type: " .. v
        end

      elseif k == "schema" then
        local rfields, err = convert_legacy_schema("fields", v)
        if err then
          return nil, err
        end
        rfields = rfields.fields.config.fields

        if v.flexible then
          new_fdata.keys = { type = "string" }
          new_fdata.values = {
            type = "record",
            required = true,
            fields = rfields,
          }
        else
          new_fdata.fields = rfields
          local rdefault = {}
          local has_default = false
          for _, field in ipairs(rfields) do
            local fname = next(field)
            local fdata = field[fname]
            if fdata.default then
              rdefault[fname] = fdata.default
              has_default = true
            end
          end
          if has_default then
            new_fdata.default = rdefault
          end
        end

      elseif k == "immutable" then
        -- FIXME really ignore?
        ngx_log(ngx_DEBUG, "Ignoring 'immutable' property")

      elseif k == "enum" then
        if old_fdata.type == "array" then
          elements.one_of = v
        else
          new_fdata.one_of = v
        end

      elseif k == "default"
          or k == "required"
          or k == "unique" then
        new_fdata[k] = v

      elseif k == "func" then
        -- FIXME some should become custom validators, some entity checks
        new_fdata.custom_validator = nil -- v

      elseif k == "new_type" then
        new_field[old_fname] = v
        break

      else
        return nil, "unknown legacy field attribute: " .. require"inspect"(k)
      end

    end
    if new_fdata.type == "array" then
      new_fdata.elements = elements
    end
    if new_fdata.type == nil then
      new_fdata.type = "string"
    end

    insert(new_schema.fields.config.fields, new_field)
  end

  if old_schema.no_route then
    insert(new_schema.fields, { route = typedefs.no_route })
  end
  if old_schema.no_service then
    insert(new_schema.fields, { service = typedefs.no_service })
  end
  if old_schema.no_consumer then
    insert(new_schema.fields, { consumer = typedefs.no_consumer })
  end
  return new_schema
end


--- Load subschemas for all configured plugins into the Plugins
-- entity, and produce a list of these plugins with their names
-- and initialized handlers.
-- @param plugin_set a set of plugin names.
-- @return an array of tables, or nil and an error message.
function Plugins:load_plugin_schemas(plugin_set)
  local plugin_list = {}
  local db = self.db

  -- load installed plugins
  for plugin in pairs(plugin_set) do
    if constants.DEPRECATED_PLUGINS[plugin] then
      ngx_log(ngx_WARN, "plugin '", plugin, "' has been deprecated")
    end

    -- NOTE: no version _G.kong (nor PDK) in plugins main chunk

    local plugin_handler = "kong.plugins." .. plugin .. ".handler"
    local ok, handler = utils.load_module_if_exists(plugin_handler)
    if not ok then
      return nil, plugin .. " plugin is enabled but not installed;\n" .. handler
    end

    local schema
    local plugin_schema = "kong.plugins." .. plugin .. ".schema"
    ok, schema = utils.load_module_if_exists(plugin_schema)
    if not ok then
      return nil, "no configuration schema found for plugin: " .. plugin
    end

    local err

    if schema.name then
      local err_t
      ok, err_t = MetaSchema.MetaSubSchema:validate(schema)
      if not ok then
        kong.log.warn("schema for plugin '", plugin, "' is invalid: ",
                      tostring(self.errors:schema_violation(err_t)))
      end

    else
      schema, err = convert_legacy_schema(plugin, schema)
      if err then
        return nil, "failed converting legacy schema for " ..
                    plugin .. ": " .. err
      end
    end

    ok, err = Entity.new_subschema(self.schema, plugin, schema)
    if not ok then
      return nil, "error initializing schema for plugin: " .. err
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

    ngx_log(ngx_DEBUG, "Loading plugin: " .. plugin)

    plugin_list[#plugin_list+1] = {
      name = plugin,
      handler = handler(),
    }

    if db.strategy then -- skip during tests
      local has_daos, daos_schemas = utils.load_module_if_exists("kong.plugins." .. plugin .. ".daos")
      if has_daos then
        local Strategy = require(fmt("kong.db.strategies.%s", db.strategy))
        local iterator = daos_schemas[1] and ipairs or pairs
        for name, schema_def in iterator(daos_schemas) do
          if name ~= "tables" and schema_def.name then
            ngx_log(ngx_DEBUG, fmt("Loading custom plugin entity: '%s.%s'", plugin, schema_def.name))
            local ok, err_t = MetaSchema:validate(schema_def)
            if not ok then
              return nil, fmt("schema of custom plugin entity '%s.%s' is invalid: %s",
                plugin, schema_def.name,
                tostring(db.errors:schema_violation(err_t)))
            end
            local schema, err = Entity.new(schema_def)
            if not schema then
              return nil, fmt("schema of custom plugin entity '%s.%s' is invalid: %s", plugin, schema_def.name,
                err)
            end
            local strategy, err = Strategy.new(db.connector, schema, db.errors)
            if not strategy then
              return nil, err
            end
            db.strategies[schema.name] = strategy

            local dao, err = DAO.new(db, schema, strategy, db.errors)
            if not dao then
              return nil, err
            end
            db.daos[schema.name] = dao
          end
        end
      end
    end
  end

  return plugin_list
end


function Plugins:select_by_cache_key(key)
  local schema_state = assert(self.db:last_schema_state())

  -- if migration is complete, disable this translator function
  -- and use the regular function
  if schema_state:is_migration_executed("core", "001_14_to_15") then
    self.select_by_cache_key = self.super.select_by_cache_key
    Plugins.select_by_cache_key = nil
    return self.super.select_by_cache_key(self, key)
  end

  -- first try new way
  local entity, new_err = self.super.select_by_cache_key(self, key)

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
    return self:row_to_entity(row)
  end

  -- when both ways have failed, return the "new" error message.
  -- otherwise, return whichever error is not-nil
  local err = (new_err and old_err) and new_err or old_err

  return nil, err
end


return Plugins
