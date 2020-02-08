local MetaSchema = require "kong.db.schema.metaschema"
local socket_url = require "socket.url"
local typedefs = require "kong.db.schema.typedefs"
local Entity = require "kong.db.schema.entity"
local utils = require "kong.tools.utils"
local go = require "kong.db.dao.plugins.go"


local plugin_loader = {}


local fmt = string.format
local next = next
local type = type
local insert = table.insert
local ipairs = ipairs


--- Check if a string is a parseable URL.
-- @param v input string string
-- @return boolean indicating whether string is an URL.
local function validate_url(v)
  if v and type(v) == "string" then
    local url = socket_url.parse(v)
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
      { config = {
        type = "record",
        required = true,
        fields = {}
      }}
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
        rfields = rfields.fields[1].config.fields

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
        kong.log.debug("ignoring 'immutable' property")

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

    if (new_fdata.type == "map" and new_fdata.keys == nil)
       or (new_fdata.type == "record" and new_fdata.fields == nil) then
      new_fdata.type = "map"
      new_fdata.keys = { type = "string" }
      new_fdata.values = { type = "string" }
    end

    if new_fdata.type == nil then
      new_fdata.type = "string"
    end

    insert(new_schema.fields[1].config.fields, new_field)
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


function plugin_loader.load_subschema(parent_schema, plugin, errors)
  local plugin_schema = "kong.plugins." .. plugin .. ".schema"
  local ok, schema = utils.load_module_if_exists(plugin_schema)
  if not ok and go.is_on() then
    ok, schema = go.load_schema(plugin)
  end

  if not ok then
    return nil, "no configuration schema found for plugin: " .. plugin
  end

  local err
  local is_legacy = false
  if not schema.name then
    is_legacy = true
    schema, err = convert_legacy_schema(plugin, schema)
  end

  if not err then
    local err_t
    ok, err_t = MetaSchema.MetaSubSchema:validate(schema)
    if not ok then
      err = tostring(errors:schema_violation(err_t))
    end
  end

  if err then
    if is_legacy then
      err = "failed converting legacy schema for " .. plugin .. ": " .. err
    end
    return nil, err
  end

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
  local iterator = daos_schemas[1] and ipairs or pairs
  local res = {}
  for name, schema_def in iterator(daos_schemas) do
    if name ~= "tables" and schema_def.name then
      local ret, err = loader_fn(plugin, schema_def, errors)
      if err then
        return nil, err
      end
      res[schema_def.name] = ret
    end
  end

  return res
end


return plugin_loader
