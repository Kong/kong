--- A schema for validating schemas
-- @module kong.db.schema.metaschema

local Schema = require("kong.db.schema")

local tablex = require("pl.tablex")


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
  { between = { type = "array", elements = { type = "integer" }, len_eq = 2 }, },
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

-- Other field attributes, that do not correspond to validators
local field_schema = {
  { type = { type = "string", one_of = tablex.keys(Schema.valid_types), required = true }, },
  { required = { type = "boolean" }, },
  { reference = { type = "string" }, },
  { auto = { type = "boolean" }, },
  { unique = { type = "boolean" }, },
  { on_delete = { type = "string", one_of = { "restrict", "cascade", "null" } }, },
  { default = { type = "self" }, },
  { abstract = { type = "boolean" }, },
  { generate_admin_api = { type = "boolean" }, },
  { legacy = { type = "boolean" }, },
  { immutable = { type = "boolean" }, },
  { err = { type = "string" } },
}

for _, field in ipairs(validators) do
  table.insert(field_schema, field)
end

-- Most of the above are optional
for _, field in ipairs(field_schema) do
  local data = field[next(field)]
  data.nilable = not data.required
end

local fields_array = {
  type = "array",
  elements = {
    type = "map",
    keys = { type = "string" },
    values = { type = "record", fields = field_schema },
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
          required = true,
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
table.insert(field_schema, { elements = { type = "record", fields = field_schema } })
table.insert(field_schema, { keys     = { type = "record", fields = field_schema } })
table.insert(field_schema, { values   = { type = "record", fields = field_schema } })
table.insert(field_schema, { fields   = fields_array })

local conditional_validators = {
  { required = { type = "boolean" } },
  { elements = { type = "record", fields = field_schema } },
  { keys     = { type = "record", fields = field_schema } },
  { values   = { type = "record", fields = field_schema } },
}
for _, field in ipairs(validators) do
  table.insert(conditional_validators, field)
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
      }
    }
  },
  { mutually_required = { type = "array", elements = { type = "string" } } },
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

for _, field in ipairs(entity_checkers) do
  local name = next(field)
  --field[name].nilable = true
  table.insert(entity_check_names, name)
end

local entity_checks_schema = {
  type = "array",
  elements = {
    type = "record",
    fields = entity_checkers,
    entity_checks = {
      { only_one_of = tablex.keys(Schema.entity_checkers) }
    }
  },
  nilable = true,
}

local shorthands_array = {
  type = "array",
  elements = {
    type = "map",
    keys = { type = "string" },
    values = { type = "function" },
    required = true,
    len_eq = 1,
  },
  nilable = true,
}

table.insert(field_schema, { entity_checks = entity_checks_schema })

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
}


local required_attributes = {
  array = { "elements" },
  set = { "elements" },
  map = { "keys", "values" },
  record = { "fields" },
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
  legacy = {
    ["string"] = true,
  },
  unique = {
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
}


local nested_attributes = {
  ["elements" ] = true,
  ["keys" ] = true,
  ["values" ] = true,
}

local check_field

local check_fields = function(schema, errors)
  for _, item in ipairs(schema.fields) do
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
      check_field(k, field, errors)
    else
      errors[k] = meta_errors.TABLE:format(k)
    end
  end
  if next(errors) then
    return nil, errors
  end
  return true
end

check_field = function(k, field, errors)
  if not field.type then
    errors[k] = meta_errors.TYPE
    return nil
  end
  if required_attributes[field.type] then
    local req_attrs = required_attributes[field.type]
    if field.abstract and field.type == "record" then
      req_attrs = {}
    end
    for _, required in ipairs(req_attrs) do
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
        check_field(k, field[name], errors)
      else
        errors[k] = meta_errors.TABLE:format(name)
      end
    end
  end
  if field.fields then
    return check_fields(field, errors)
  end
end


local function has_schema_field(schema, name)
  if schema == nil then
    return false
  end

  local dot = string.find(name, ".", 1, true)
  if not dot then
    for _, field in ipairs(schema.fields) do
      local k = next(field)
      if k == name then
        return true
      end
    end

    return false
  end

  local hd, tl = string.sub(name, 1, dot - 1), string.sub(name, dot + 1)
  for _, field in ipairs(schema.fields) do
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
      admin_api_nested_name = {
        type = "string",
        nilable = true,
      },
    },
    {
      legacy = {
        type = "boolean",
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
      shorthands = shorthands_array,
    },
    {
      check = {
        type = "function",
        nilable = true
      },
    },
    {
      dao = {
        type = "string",
        nilable = true
      },
    },
    {
      transformations = transformations_array,
    },
  },

  check = function(schema)
    local errors = {}

    if not schema.fields then
      errors["fields"] = meta_errors.TABLE:format("fields")
      return nil, errors
    end

    if schema.endpoint_key then
      local found = false
      for _, item in ipairs(schema.fields) do
        local k = next(item)
        if schema.endpoint_key == k then
          found = true
          break
        end
      end
      if not found then
        errors["endpoint_key"] = meta_errors.ENDPOINT_KEY
      end
    end

    if schema.cache_key then
      local found
      for _, e in ipairs(schema.cache_key) do
        found = nil
        for _, item in ipairs(schema.fields) do
          local k = next(item)
          if e == k then
            found = item[k]
            break
          end
        end
        if not found then
          errors["cache_key"] = meta_errors.CACHE_KEY
          break
        end
      end
      if #schema.cache_key == 1 then
        if found and not found.unique then
          errors["cache_key"] = meta_errors.CACHE_KEY_UNIQUE
        end
      end
    end

    if schema.subschema_key then
      local found = false
      for _, item in ipairs(schema.fields) do
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
      for _, item in ipairs(schema.fields) do
        local k = next(item)
        if k == "ttl" then
          errors["ttl"] = meta_errors.TTL_RESERVED
          break
        end
      end
    end

    if schema.transformations then
      for i, transformation in ipairs(schema.transformations) do
        for j, input in ipairs(transformation.input) do
          if not has_schema_field(schema, input) then
            if not errors.transformations then
              errors.transformations = {}
            end

            if not errors.transformations.input then
              errors.transformations.input = {}
            end


            if not errors.transformations.input[i] then
              errors.transformations.input[i] = {}
            end

            errors.transformations.input[i][j] = string.format("invalid field name: %s", input)
          end
        end

        if transformation.needs then
          for j, need in ipairs(transformation.needs) do
            if not has_schema_field(schema, need) then
              if not errors.transformations then
                errors.transformations = {}
              end

              if not errors.transformations.needs then
                errors.transformations.needs = {}
              end


              if not errors.transformations.needs[i] then
                errors.transformations.needs[i] = {}
              end

              errors.transformations.needs[i][j] = string.format("invalid field name: %s", need)
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
  for _, item in ipairs(validators) do
    local name = next(item)
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
      shorthands = shorthands_array,
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
