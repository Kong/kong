--- A schema for validating schemas
-- @module kong.db.schema.metaschema

local Schema = require "kong.db.schema"
local json_lib = require "kong.db.schema.json"
local constants = require "kong.constants"


local setmetatable = setmetatable
local assert = assert
local insert = table.insert
local pairs = pairs
local find = string.find
local type = type
local next = next
local keys = require("pl.tablex").keys
local values = require("pl.tablex").values
local sub = string.sub
local fmt = string.format


local match_list = {
  type = "array",
  elements = {
    type = "record",
    fields = {
      { pattern = { type = "string", required = true } },
      { err = { type = "string" } },
    }
  }
}


local match_any_list = {
  type = "record",
  fields = {
    { patterns = {
        type = "array",
        elements = { type = "string" },
        required = true
    } },
    { err = { type = "string" } },
  }
}

-- Field attributes which match a validator function in the Schema class
local validators = {
  { between = { type = "array", elements = { type = "number" }, len_eq = 2 }, },
  { eq = { type = "any" }, },
  { ne = { type = "any" }, },
  { gt = { type = "number" }, },
  { len_eq = { type = "integer" }, },
  { len_min = { type = "integer" }, },
  { len_max = { type = "integer" }, },
  { match = { type = "string" }, },
  { not_match = { type = "string" }, },
  { match_all = match_list },
  { match_none = match_list },
  { match_any = match_any_list },
  { starts_with = { type = "string" }, },
  { one_of = { type = "array", elements = { type = "any" } }, },
  { not_one_of = { type = "array", elements = { type = "any" } }, },
  { contains = { type = "any" }, },
  { is_regex = { type = "boolean" }, },
  { timestamp = { type = "boolean" }, },
  { uuid = { type = "boolean" }, },
  { custom_validator = { type = "function" }, },
  { mutually_exclusive_subsets = { type = "array", elements = { type = "array", elements = { type = "string" } } } },
}

-- JSON schema is supported in two different methods:
--
-- * inline: the JSON schema is defined in the field itself
-- * dynamic/reference: the JSON schema is stored in the database
--
-- Inline schemas have the JSON schema definied statically within
-- the typedef's `json_schema.inline` field. Example:
--
-- ```lua
-- local field = {
--   type = "json",
--   json_schema = {
--     inline = {
--       type = "object",
--       properties = {
--         foo = { type = "string" },
--       },
--     },
--   }
-- }
--
-- local record = {
--   type = "record",
--   fields = {
--     { name = { type = "string" } },
--     { config = field },
--   },
-- }
--
-- ```
--
-- Fields with dynamic schemas function similarly to Lua subschemas, wherein
-- the contents of the input are used to generate a string key that is used
-- to lookup the schema from the schema storage. Example:
--
-- ```lua
-- local record = {
--   type = "record",
--   fields = {
--     { name = { type = "string" } },
--     { config = {
--         type = "json",
--         json_schema = {
--           namespace = "my-record-type",
--           parent_subschema_key = "name",
--           optional = true,
--         },
--       },
--     },
--   },
-- }
-- ```
--
-- In this case, an input value of `{ name = "foo", config = "foo config" }`
-- will cause the validation engine to lookup a schema by the name of
-- `my-record-type/foo`. The `optional` field determines what will happen if
-- the schema does not exist. When `optional` is `false`, a missing schema
-- means that input validation will fail. When `optional` is `true`, the input
-- is always accepted.
--
-- Schemas which use this dynamic reference format can also optionally supply
-- a default inline schema, which will be evaluated when the dynamic schema
-- does not exist:
--
-- ```lua
-- local record = {
--   type = "record",
--   fields = {
--     { name = { type = "string" } },
--     { config = {
--         type = "json",
--         json_schema = {
--           namespace = "my-record-type",
--           parent_subschema_key = "name",
--           default = {
--             { type = { "string", "null" } },
--           },
--         },
--       },
--     },
--   },
-- }
-- ```
--
local json_metaschema = {
  type = "record",
  fields = {
    { namespace = { type = "string", one_of = values(constants.SCHEMA_NAMESPACES), }, },
    { parent_subschema_key = { type = "string" }, },
    { optional = { type = "boolean", }, },
    { inline = { type = "any", custom_validator = json_lib.validate_schema, }, },
    { default = { type = "any", custom_validator = json_lib.validate_schema, }, },
  },
  entity_checks = {
    { at_least_one_of = { "inline", "namespace", "parent_subschema_key" }, },
    { mutually_required = { "namespace", "parent_subschema_key" }, },
    { mutually_exclusive_sets = {
        set1 = { "inline" },
        set2 = { "namespace", "parent_subschema_key", "optional" },
      },
    },
  },
}


-- Other field attributes, that do not correspond to validators
local field_schema = {
  { type = { type = "string", one_of = keys(Schema.valid_types), required = true }, },
  { required = { type = "boolean" }, },
  { reference = { type = "string" }, },
  { description = { type = "string", len_min = 10, len_max = 500}, },
  { examples = { type = "array", elements = { type = "any" } } },
  { auto = { type = "boolean" }, },
  { unique = { type = "boolean" }, },
  { unique_across_ws = { type = "boolean" }, },
  { on_delete = { type = "string", one_of = { "restrict", "cascade", "null" } }, },
  { default = { type = "self" }, },
  { abstract = { type = "boolean" }, },
  { generate_admin_api = { type = "boolean" }, },
  { immutable = { type = "boolean" }, },
  { err = { type = "string" } },
  { encrypted = { type = "boolean" }, },
  { referenceable = { type = "boolean" }, },
  { json_schema = json_metaschema },
}


for i = 1, #validators do
  insert(field_schema, validators[i])
end


-- Most of the above are optional
for i = 1, #field_schema do
  local field = field_schema[i]
  local data = field[next(field)]
  data.nilable = not data.required
end


local field_entity_checks = {
  -- if 'unique_across_ws' is set, then 'unique' must be set too
  {
    conditional = {
      if_field = "unique_across_ws", if_match = { eq = true },
      then_field = "unique", then_match = { eq = true, required = true },
    }
  },
}


local fields_array = {
  type = "array",
  elements = {
    type = "map",
    keys = { type = "string" },
    values = { type = "record", fields = field_schema, entity_checks = field_entity_checks },
    required = true,
    len_eq = 1,
  },
}


local transformations_array = {
  type = "array",
  nilable = true,
  elements = {
    type = "record",
    fields = {
      {
        input = {
          type = "array",
          required = false,
          elements = {
            type = "string"
          },
        },
      },
      {
        needs = {
          type = "array",
          required = false,
          elements = {
            type = "string"
          },
        }
      },
      {
        on_write = {
          type = "function",
          required = false,
        },
      },
      {
        on_read = {
          type = "function",
          required = false,
        },
      },
    },
    entity_checks = {
      {
        at_least_one_of = {
          "on_write",
          "on_read",
        },
      },
    },
  },
}


-- Recursive field attributes
insert(field_schema, { elements = { type = "record", fields = field_schema } })
insert(field_schema, { keys     = { type = "record", fields = field_schema } })
insert(field_schema, { values   = { type = "record", fields = field_schema } })
insert(field_schema, { fields   = fields_array })


local conditional_validators = {
  { required = { type = "boolean" } },
  { elements = { type = "record", fields = field_schema } },
  { keys     = { type = "record", fields = field_schema } },
  { values   = { type = "record", fields = field_schema } },
}
for i = 1, #validators do
  insert(conditional_validators, validators[i])
end


local entity_checkers = {
  { at_least_one_of = { type = "array", elements = { type = "string" } } },
  { conditional_at_least_one_of = {
      type = "record",
      fields = {
        { if_field = { type = "string" } },
        { if_match = { type = "record", fields = conditional_validators } },
        { then_at_least_one_of = { type = "array", elements = { type = "string" } } },
        { then_err = { type = "string" } },
        { else_match = { type = "record", fields = conditional_validators } },
        { else_then_at_least_one_of = { type = "array", elements = { type = "string" } } },
        { else_then_err = { type = "string" } },
      },
    },
  },
  { only_one_of     = { type = "array", elements = { type = "string" } } },
  { distinct        = { type = "array", elements = { type = "string" } }, },
  { conditional     = {
      type = "record",
      fields = {
        { if_field = { type = "string" } },
        { if_match = { type = "record", fields = conditional_validators } },
        { then_field = { type = "string" } },
        { then_match = { type = "record", fields = conditional_validators } },
        { then_err = { type = "string" } },
      },
    },
  },
  { custom_entity_check = {
      type = "record",
      fields = {
        { field_sources = { type = "array", elements = { type = "string" } } },
        { fn = { type = "function" } },
        { run_with_missing_fields = { type = "boolean" } },
        { run_with_invalid_fields = { type = "boolean" } },
      }
    }
  },
  { mutually_required = { type = "array", elements = { type = "string" } } },
  { mutually_exclusive = { type = "array", elements = { type = "string" } } },
  { mutually_exclusive_sets = {
      type = "record",
      fields = {
        { set1 = {type = "array", elements = {type = "string"} } },
        { set2 = {type = "array", elements = {type = "string"} } },
      }
    }
  },
}


local entity_check_names = {}


for i = 1, #entity_checkers do
  local field = entity_checkers[i]
  local name = next(field)
  --field[name].nilable = true
  insert(entity_check_names, name)
end


local entity_checks_schema = {
  type = "array",
  elements = {
    type = "record",
    fields = entity_checkers,
    entity_checks = {
      { only_one_of = keys(Schema.entity_checkers) }
    }
  },
  nilable = true,
}


local shorthand_fields_array = {
  type = "array",
  elements = {
    type = "map",
    keys = { type = "string" },
    -- values are defined below after field_schema definition is complete
    required = true,
    len_eq = 1,
  },
  nilable = true,
}


insert(field_schema, { entity_checks = entity_checks_schema })
insert(field_schema, { shorthand_fields = shorthand_fields_array })


local meta_errors = {
  ATTRIBUTE = "field of type '%s' cannot have attribute '%s'",
  REQUIRED = "field of type '%s' must declare '%s'",
  TABLE = "'%s' must be a table",
  BOOLEAN = "'%s' must be a boolean",
  TYPE = "missing type declaration",
  FIELD_EMPTY = "field entry table is empty",
  FIELDS_ARRAY = "each entry in fields must be a sub-table",
  FIELDS_KEY = "each key in fields must be a string",
  ENDPOINT_KEY = "value must be a field name",
  CACHE_KEY = "values must be field names",
  CACHE_KEY_UNIQUE = "a field used as a single cache key must be unique",
  TTL_RESERVED = "ttl is a reserved field name when ttl is enabled",
  SUBSCHEMA_KEY = "value must be a field name",
  SUBSCHEMA_KEY_TYPE = "must be a string or set field",
  JSON_PARENT_KEY = "value must be a field name of the parent schema",
  JSON_PARENT_KEY_TYPE = "value must be a string field of the parent schema",
}


local required_attributes = {
  array = { "elements" },
  set = { "elements" },
  map = { "keys", "values" },
  record = { "fields" },
  json = { "json_schema" },
}


local attribute_types = {
  between = {
    ["integer"] = true,
    ["number"] = true,
  },
  len_eq = {
    ["array"]  = true,
    ["set"]    = true,
    ["string"] = true,
    ["map"]    = true,
  },
  match = {
    ["string"] = true,
  },
  one_of = {
    ["string"] = true,
    ["number"] = true,
    ["integer"] = true,
  },
  contains = {
    ["array"] = true,
    ["set"]   = true,
  },
  is_regex = {
    ["string"] = true,
  },
  timestamp = {
    ["number"] = true,
    ["integer"] = true,
  },
  uuid = {
    ["string"] = true,
  },
  unique = {
    ["string"] = true,
    ["number"] = true,
    ["integer"] = true,
    ["foreign"] = true,
  },
  unique_across_ws = {
    ["string"] = true,
    ["number"] = true,
    ["integer"] = true,
    ["foreign"] = true,
  },
  abstract = {
    ["string"] = true,
    ["number"] = true,
    ["integer"] = true,
    ["record"] = true,
    ["array"] = true,
    ["set"] = true,
    ["map"] = true,
  },
  json_schema = {
    ["json"] = true,
  },
}


local nested_attributes = {
  ["elements" ] = true,
  ["keys" ] = true,
  ["values" ] = true,
}


local check_field


local function has_schema_field(schema, name)
  if schema == nil then
    return false
  end

  local fields = schema.fields
  local fields_count = #fields

  local dot = find(name, ".", 1, true)
  if not dot then
    for i = 1, fields_count do
      local field = fields[i]
      local k = next(field)
      if k == name then
        return true
      end
    end

    return false
  end

  local hd, tl = sub(name, 1, dot - 1), sub(name, dot + 1)
  for i = 1, fields_count do
    local field = fields[i]
    local k = next(field)
    if k == hd then
      if field[hd] and field[hd].type == "foreign" then
        -- metaschema has no access to foreign schemas
        -- so we just trust the developer of the schema.

        return true
      end

      return has_schema_field(field[hd], tl)
    end
  end

  return false
end

local check_fields = function(schema, errors)
  local transformations = schema.transformations
  if transformations then
    for i = 1, #transformations do
      local transformation = transformations[i]
      if transformation.input then
        for j = 1, #transformation.input do
          local input = transformation.input[j]
          if not has_schema_field(schema, input) then
            errors.transformations = errors.transformations or {}
            errors.transformations.input = errors.transformations.input or {}
            errors.transformations.input[i] = errors.transformations.input[i] or {}
            errors.transformations.input[i][j] = fmt("invalid field name: %s", input)
          end
        end
      end

      if transformation.needs then
        for j = 1, #transformation.needs do
          local need = transformation.needs[j]
          if not has_schema_field(schema, need) then
            errors.transformations = errors.transformations or {}
            errors.transformations.needs = errors.transformations.needs or {}
            errors.transformations.needs[i] = errors.transformations.needs[i] or {}
            errors.transformations.needs[i][j] = fmt("invalid field name: %s", need)
          end
        end
      end
    end
  end

  for i = 1, #schema.fields do
    local item = schema.fields[i]
    if type(item) ~= "table" then
      errors["fields"] = meta_errors.FIELDS_ARRAY
      break
    end
    local k = next(item)
    if not k then
      errors["fields"] = meta_errors.FIELD_EMPTY
      break
    end
    local field = item[k]
    if type(field) == "table" then
      check_field(k, field, errors, schema)
    else
      errors[k] = meta_errors.TABLE:format(k)
    end
  end
  if next(errors) then
    return nil, errors
  end
  return true
end


check_field = function(k, field, errors, parent_schema)
  if not field.type then
    errors[k] = meta_errors.TYPE
    return nil
  end
  if required_attributes[field.type] then
    local req_attrs = required_attributes[field.type]
    if field.abstract and field.type == "record" then
      req_attrs = {}
    end
    for i = 1, #req_attrs do
      local required = req_attrs[i]
      if not field[required] then
        errors[k] = meta_errors.REQUIRED:format(field.type, required)
      end
    end
  end
  for attr, _ in pairs(field) do
    if attribute_types[attr] and not attribute_types[attr][field.type] then
      errors[k] = meta_errors.ATTRIBUTE:format(field.type, attr)
    end
  end
  for name, _ in pairs(nested_attributes) do
    if field[name] then
      if type(field[name]) == "table" then
        check_field(k, field[name], errors, field)
      else
        errors[k] = meta_errors.TABLE:format(name)
      end
    end
  end

  if field.type == "json"
    and field.json_schema
    and field.json_schema.parent_subschema_key
  then
    local parent_subschema_key = field.json_schema.parent_subschema_key
    local found = false

    for i = 1, #parent_schema.fields do
      local item = parent_schema.fields[i]
      local parent_field_name = next(item)
      local parent_field = item[parent_field_name]

      if parent_subschema_key == parent_field_name then
        if parent_field.type ~= "string" then
          errors[k] = errors[k] or {}
          errors[k].json_schema = {
            parent_subschema_key = meta_errors.JSON_PARENT_KEY_TYPE
          }
        end
        found = true
        break
      end
    end

    if not found then
      errors[k] = errors[k] or {}
      errors[k].json_schema = {
        parent_subschema_key = meta_errors.JSON_PARENT_KEY
      }
      return
    end
  end

  if field.fields then
    return check_fields(field, errors)
  end
end


-- Build a variant of the field_schema, adding a 'func' attribute
-- and restricting the set of valid types.
local function make_shorthand_field_schema()
  local shorthand_field_schema = {}
  for k, v in pairs(field_schema) do
    shorthand_field_schema[k] = v
  end

  -- do not accept complex/recursive types
  -- which require additional schema processing as shorthands
  local invalid_as_shorthand = {
    record = true,
    foreign = true,
    ["function"] = true,
  }

  local shorthand_field_types = {}
  for k in pairs(Schema.valid_types) do
    if not invalid_as_shorthand[k] then
      insert(shorthand_field_types, k)
    end
  end

  assert(next(shorthand_field_schema[1]) == "type")
  shorthand_field_schema[1] = { type = { type = "string", one_of = shorthand_field_types, required = true }, }

  insert(shorthand_field_schema, { func = { type = "function", required = true } })
  insert(shorthand_field_schema, { translate_backwards = { type = "array", elements = { type = "string" }, required = false } })
  return shorthand_field_schema
end


shorthand_fields_array.elements.values = {
  type = "record",
  fields = make_shorthand_field_schema(),
  entity_checks = field_entity_checks
}


local MetaSchema = Schema.new({
  name = "metaschema",
  fields = {
    {
      name = {
        type = "string",
        required = true
      },
    },
    {
      primary_key = {
        type = "array",
        elements = { type = "string" },
        required = true,
      },
    },
    {
      workspaceable = {
        type = "boolean",
        nilable = true
      },
    },
    {
      endpoint_key = {
        type = "string",
        nilable = true,
      },
    },
    {
      cache_key = {
        type = "array",
        elements = {
          type = "string",
        },
        nilable = true,
      },
    },
    {
      ttl = {
        type = "boolean",
        nilable = true,
      }
    },
    {
      db_export = {
        type = "boolean",
        nilable = true,
        default = true,
      }
    },
    {
      subschema_key = {
        type = "string",
        nilable = true,
      },
    },
    {
      subschema_error = {
        type = "string",
        nilable = true,
      },
    },
    {
      generate_admin_api = {
        type = "boolean",
        nilable = true,
        default = true,
      },
    },
    {
      admin_api_name = {
        type = "string",
        nilable = true,
      },
    },
    {
      table_name = {
        type = "string",
        nilable = true,
      },
    },
    {
      admin_api_nested_name = {
        type = "string",
        nilable = true,
      },
    },
    {
      fields = fields_array,
    },
    {
      entity_checks = entity_checks_schema,
    },
    {
      shorthand_fields = shorthand_fields_array,
    },
    {
      transformations = transformations_array,
    },
    {
      check = {
        type = "function",
        nilable = true,
      },
    },
    {
      dao = {
        type = "string",
        nilable = true
      },
    },
  },

  check = function(schema)
    local errors = {}
    local fields = schema.fields

    if not fields then
      errors["fields"] = meta_errors.TABLE:format("fields")
      return nil, errors
    end

    if not schema.table_name then
      schema.table_name = schema.name
    end

    if schema.endpoint_key then
      local found = false
      for i = 1, #fields do
        local k = next(fields[i])
        if schema.endpoint_key == k then
          found = true
          break
        end
      end
      if not found then
        errors["endpoint_key"] = meta_errors.ENDPOINT_KEY
      end
    end

    local cache_key = schema.cache_key
    if cache_key then
      local found
      for i = 1, #cache_key do
        found = nil
        for j = 1, #fields do
          local item = fields[j]
          local k = next(item)
          if cache_key[i] == k then
            found = item[k]
            break
          end
        end
        if not found then
          errors["cache_key"] = meta_errors.CACHE_KEY
          break
        end
      end

      if #cache_key == 1 then
        if found and not found.unique then
          errors["cache_key"] = meta_errors.CACHE_KEY_UNIQUE
        end
      end
    end

    if schema.subschema_key then
      local found = false
      for i = 1, #fields do
        local item = fields[i]
        local k = next(item)
        local field = item[k]
        if schema.subschema_key == k then
          if field.type ~= "string" and field.type ~= "set" then
            errors["subschema_key"] = meta_errors.SUBSCHEMA_KEY_TYPE
          end
          found = true
          break
        end
      end
      if not found then
        errors["subschema_key"] = meta_errors.SUBSCHEMA_KEY
      end
    end

    if schema.ttl then
      for i = 1, #fields do
        local k = next(fields[i])
        if k == "ttl" then
          errors["ttl"] = meta_errors.TTL_RESERVED
          break
        end
      end
    end

    local transformations = schema.transformations
    if transformations then
      for i = 1, #transformations do
        local input = transformations[i].input
        if input then
          for j = 1, #input do
            if not has_schema_field(schema, input[j]) then
              if not errors.transformations then
                errors.transformations = {}
              end

              if not errors.transformations.input then
                errors.transformations.input = {}
              end


              if not errors.transformations.input[i] then
                errors.transformations.input[i] = {}
              end

              errors.transformations.input[i][j] = fmt("invalid field name: %s", input)
            end
          end
        end

        local needs = transformations[i].needs
        if needs then
          for j = 1, #needs do
            if not has_schema_field(schema, needs[j]) then
              if not errors.transformations then
                errors.transformations = {}
              end

              if not errors.transformations.needs then
                errors.transformations.needs = {}
              end


              if not errors.transformations.needs[i] then
                errors.transformations.needs[i] = {}
              end

              errors.transformations.needs[i][j] = fmt("invalid field name: %s", needs[j])
            end
          end
        end
      end
    end

    return check_fields(schema, errors)
  end,
})


MetaSchema.valid_types = setmetatable({
  ["function"] = true,
}, { __index = Schema.valid_types })


--- Produce a list of validators understood by the MetaSchema.
-- This list is produced from the MetaSchema definition and
-- is used for cross-checking against the Schema validators.
-- @return a set of validator names.
function MetaSchema.get_supported_validator_set()
  local set = {}
  for i = 1, #validators do
    local name = next(validators[i])
    set[name] = true
  end
  return set
end


MetaSchema.MetaSubSchema = Schema.new({
  name = "metasubschema",
  fields = {
    {
      name = {
        type = "string",
        required = true,
      },
    },
    {
      fields = fields_array,
    },
    {
      entity_checks = entity_checks_schema,
    },
    {
      shorthand_fields = shorthand_fields_array,
    },
    {
      transformations = transformations_array,
    },
    {
      check = {
        type = "function",
        nilable = true,
      },
    },
  },
  check = function(schema)
    local errors = {}

    if not schema.fields then
      errors["fields"] = meta_errors.TABLE:format("fields")
      return nil, errors
    end

    return check_fields(schema, errors)
  end,
})


return MetaSchema
