-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local MetaSchema = require "kong.db.schema.metaschema"
local Entity = require "kong.db.schema.entity"
local plugin_servers = require "kong.runloop.plugin_servers"
local wasm_plugins = require "kong.runloop.wasm.plugins"
local is_array = require "kong.tools.table".is_array
local load_module_if_exists = require "kong.tools.module".load_module_if_exists
local sandbox_schema = require("kong.tools.sandbox").sandbox_schema


local fmt = string.format
local type = type
local pcall = pcall
local tostring = tostring


local function load_custom_plugin_subschema(plugin)
  local name = plugin.name
  local chunk = plugin.schema
  if type(chunk) == "table" then
    return chunk
  end

  local ok, compiled = pcall(sandbox_schema, chunk, name)
  if not ok then
    return nil, fmt("compiling custom '%s' plugin schema failed: %s", name, compiled)
  end

  local ok, schema = pcall(compiled)
  if not ok then
    return nil, fmt("loading custom '%s' plugin schema failed: %s", name, schema)
  end

  return schema
end


local plugin_loader = {}


function plugin_loader.load_subschema(parent_schema, name, errors)
  local plugin_schema = "kong.plugins." .. name .. ".schema"
  local ok, definition = load_module_if_exists(plugin_schema)
  if not ok then
    ok, definition = wasm_plugins.load_schema(name)
  end
  if not ok then
    ok, definition = plugin_servers.load_schema(name)
  end

  if not ok then
    return nil, "no configuration schema found for plugin: " .. name
  end

  local ok, err_t = MetaSchema.MetaSubSchema:validate(definition)
  if not ok then
    return nil, tostring(errors:schema_violation(err_t))
  end

  local subschema, err = Entity.new_subschema(parent_schema, name, definition)
  if not ok then
    return nil, "error initializing schema for plugin: " .. err
  end

  return definition, nil, subschema
end


function plugin_loader.load_custom_subschema(parent_schema, plugin, errors)
  local definition, err = load_custom_plugin_subschema(plugin)
  if not definition then
    return nil, err
  end

  local ok, err_t = MetaSchema.RestrictedMetaSubSchema:validate(definition)
  if not ok then
    return nil, tostring(errors:schema_violation(err_t))
  end

  local subschema, err = Entity.load_and_validate_subschema(parent_schema, plugin.name, definition)
  if not subschema then
    return nil, err
  end

  return definition, nil, subschema
end


function plugin_loader.reset_custom_subschema(parent_schema, name, definition, subschema)
  Entity.reset_subschema(parent_schema, name, definition, subschema)
end


function plugin_loader.load_entity_schema(name, definition, errors)
  local _, err_t = MetaSchema:validate(definition)
  if err_t then
    return nil, fmt("schema of custom plugin entity '%s.%s' is invalid: %s",
      name, definition.name, tostring(errors:schema_violation(err_t)))
  end

  local schema, err = Entity.new(definition)
  if err then
    return nil, fmt("schema of custom plugin entity '%s.%s' is invalid: %s",
      name, definition.name, err)
  end

  return schema
end


function plugin_loader.load_entities(name, errors, loader_fn)
  local has_daos, daos_schemas = load_module_if_exists("kong.plugins." .. name .. ".daos")
  if not has_daos then
    return {}
  end
  if not is_array(daos_schemas, "strict") then
    return nil, fmt("custom plugin '%s' returned non-array daos definition table", name)
  end

  local res = {}
  local definition, ret, err
  for i = 1, #daos_schemas do
    definition = daos_schemas[i]
    ret, err = loader_fn(name, definition, errors)
    if err then
      return nil, err
    end
    res[definition.name] = ret
  end

  return res
end


return plugin_loader
