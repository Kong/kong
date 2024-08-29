local MetaSchema = require "kong.db.schema.metaschema"
local Entity = require "kong.db.schema.entity"
local plugin_servers = require "kong.runloop.plugin_servers"
local is_array = require "kong.tools.table".is_array
local load_module_if_exists = require "kong.tools.module".load_module_if_exists


local fmt = string.format
local tostring = tostring


local SUBSCHEMA_CACHE = setmetatable({}, { __mode = "kv" })


local plugin_loader = {}


function plugin_loader.load_subschema(parent_schema, plugin, errors)
  local schema = SUBSCHEMA_CACHE[plugin]
  if not schema then
    local ok
    ok, schema = load_module_if_exists("kong.plugins." .. plugin .. ".schema")
    if not ok then
      ok, schema = plugin_servers.load_schema(plugin)
    end

    if not ok then
      return nil, "no configuration schema found for plugin: " .. plugin
    end

    local err_t
    ok, err_t = MetaSchema.MetaSubSchema:validate(schema)
    if not ok then
      return nil, tostring(errors:schema_violation(err_t))
    end

    SUBSCHEMA_CACHE[plugin] = schema
  end

  if not SUBSCHEMA_CACHE[parent_schema] then
    SUBSCHEMA_CACHE[parent_schema] = {}
  end

  if not SUBSCHEMA_CACHE[parent_schema][plugin] then
    SUBSCHEMA_CACHE[parent_schema][plugin] = true
    local ok, err = Entity.new_subschema(parent_schema, plugin, schema)
    if not ok then
      return nil, "error initializing schema for plugin: " .. err
    end
  end

  return schema
end


function plugin_loader.load_entity_schema(plugin, schema_def, errors)
  local _, err_t = MetaSchema:validate(schema_def)
  if err_t then
    return nil, fmt("schema of custom plugin entity '%s.%s' is invalid: %s",
      plugin, schema_def.name, tostring(errors:schema_violation(err_t)))
  end

  local schema, err = Entity.new(schema_def)
  if err then
    return nil, fmt("schema of custom plugin entity '%s.%s' is invalid: %s",
                    plugin, schema_def.name, err)
  end

  return schema
end


function plugin_loader.load_entities(plugin, errors, loader_fn)
  local has_daos, daos_schemas = load_module_if_exists("kong.plugins." .. plugin .. ".daos")
  if not has_daos then
    return {}
  end
  if not is_array(daos_schemas, "strict") then
    return nil, fmt("custom plugin '%s' returned non-array daos definition table", plugin)
  end

  local res = {}
  local schema_def, ret, err
  for i = 1, #daos_schemas do
    schema_def = daos_schemas[i]
    ret, err = loader_fn(plugin, schema_def, errors)
    if err then
      return nil, err
    end
    res[schema_def.name] = ret
  end

  return res
end


return plugin_loader
