local constants = require "kong.constants"
local typedefs = require "kong.db.schema.typedefs"
local utils = require "kong.tools.utils"


local Plugins = {}


local null = ngx.null
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local ngx_DEBUG = ngx.DEBUG


--- Given a set of plugin names, check if all plugins stored
-- in the database fall into this set.
-- @param plugin_set a set of plugin names.
-- @return true or nil and an error message.
function Plugins:check_db_against_config(plugin_set)
  local in_db_plugins = {}
  ngx_log(ngx_DEBUG, "Discovering used plugins")

  for row, err in self:each() do
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
        nullable = false,
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
          if old_fdata.schema.flexible then
            new_fdata.type = "map"
          else
            new_fdata.type = "record"
            new_fdata.nullable = false
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
            nullable = false,
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

    table.insert(new_schema.fields.config.fields, new_field)
  end

  if old_schema.no_api then
    table.insert(new_schema.fields, { api = typedefs.no_api })
  end
  if old_schema.no_route then
    table.insert(new_schema.fields, { route = typedefs.no_route })
  end
  if old_schema.no_service then
    table.insert(new_schema.fields, { service = typedefs.no_service })
  end
  if old_schema.no_consumer then
    table.insert(new_schema.fields, { consumer = typedefs.no_consumer })
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

    if not schema.name then
      schema, err = convert_legacy_schema(plugin, schema)
      if err then
        return nil, "failed converting legacy schema for " ..
                    plugin .. ": " .. err
      end
    end

    ok, err = self.schema:new_subschema(plugin, schema)
    if not ok then
      return nil, "error initializing schema for plugin: " .. err
    end

    if schema.fields.api and schema.fields.api.eq == null then
      plugin.no_api = true
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
  end

  return plugin_list
end


return Plugins
