local MetaSchema = require "kong.db.schema.metaschema"
local Entity = require "kong.db.schema.entity"
local utils = require "kong.tools.utils"
local plugin_servers = require "kong.runloop.plugin_servers"
local utils_toposort = utils.topological_sort


local plugin_loader = {}


local fmt = string.format
local next = next
local sort = table.sort
local pairs = pairs
local ipairs = ipairs
local tostring = tostring


-- Given a hash of daos_schemas (a hash of tables,
-- direct parsing of a plugin's daos.lua file) return an array
-- of schemas in which:
-- * If entity B has a foreign key to A, then B appears after A
-- * If there's no foreign keys, schemas are sorted alphabetically by name
local function sort_daos_schemas_topologically(daos_schemas)
  local schema_defs = {}
  local len = 0
  local schema_defs_by_name = {}

  for name, schema_def in pairs(daos_schemas) do
    if name ~= "tables" or schema_def.fields then
      len = len + 1
      schema_defs[len] = schema_def
      schema_defs_by_name[schema_def.name] = schema_def
    end
  end

  -- initially sort by schema name
  sort(schema_defs, function(a, b)
    return a.name > b.name
  end)

  -- given a schema_def, return all the schema defs to which it has references
  -- (and are on the list of schemas provided)
  local get_schema_def_neighbors = function(schema_def)
    local neighbors = {}
    local neighbors_len = 0
    local neighbor

    for _, field in ipairs(schema_def.fields) do
      if field.type == "foreign"  then
        neighbor = schema_defs_by_name[field.reference] -- services
        if neighbor then
          neighbors_len = neighbors_len + 1
          neighbors[neighbors_len] = neighbor
        end
        -- else the neighbor points to an unknown/uninteresting schema. This might happen in tests.
      end
    end

    return neighbors
  end

  return utils_toposort(schema_defs, get_schema_def_neighbors)
end


function plugin_loader.load_subschema(parent_schema, plugin, errors)
  local plugin_schema = "kong.plugins." .. plugin .. ".schema"
  local ok, schema = utils.load_module_if_exists(plugin_schema)
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

  local err
  ok, err = Entity.new_subschema(parent_schema, plugin, schema)
  if not ok then
    return nil, "error initializing schema for plugin: " .. err
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
  local has_daos, daos_schemas = utils.load_module_if_exists("kong.plugins." .. plugin .. ".daos")
  if not has_daos then
    return {}
  end
  if not daos_schemas[1] and next(daos_schemas) then
    -- daos_schemas is a non-empty hash (old syntax). Sort it topologically in order to avoid errors when loading
    -- relationships before loading entities within the same plugin
    daos_schemas = sort_daos_schemas_topologically(daos_schemas)

    kong.log.deprecation("The plugin ", plugin,
     " is using a hash-like syntax on its `daos.lua` file. ",
     "Please replace the hash table with a sequential array of schemas.",
     { after = "2.6.0", removal = "3.0.0" })
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
