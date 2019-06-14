--- THIS MODULE WAS IMPORTED FROM KONG
-- Contains a fix not currently in Kong EE's version:
-- https://github.com/Kong/kong/commit/a2ed1da2c549d6c0131edab4e59b3486a8032784
--
-- A schema for validating schemas
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
  { len_eq = { type = "integer" }, },
  { len_min = { type = "integer" }, },
  { len_max = { type = "integer" }, },
  { match = { type = "string" }, },
  { not_match = { type = "string" }, },
  { match_all = match_list },
  { match_none = match_list },
  { match_any = match_any_list },
  { starts_with = { type = "string" }, },
  { one_of = { type = "array", elements = { type = "string" } }, },
  { timestamp = { type = "boolean" }, },
  { uuid = { type = "boolean" }, },
  { custom_validator = { type = "function" }, },
}

-- Other field attributes, that do not correspond to validators
local field_schema = {
  { type = { type = "string", one_of = tablex.keys(Schema.valid_types), required = true }, },
  { required = { type = "boolean" }, },
  { reference = { type = "string" }, },
  { auto = { type = "boolean" }, },
  { unique = { type = "boolean" }, },
  { default = { type = "self" }, },
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

-- Recursive field attributes
table.insert(field_schema, { elements = { type = "record", fields = field_schema } })
table.insert(field_schema, { keys     = { type = "record", fields = field_schema } })
table.insert(field_schema, { values   = { type = "record", fields = field_schema } })
table.insert(field_schema, { fields   = fields_array })

local conditional_validators = {}
for _, field in ipairs(validators) do
  table.insert(conditional_validators, field)
end

local entity_checkers = {
  { at_least_one_of = { type = "array", elements = { type = "string" } } },
  { only_one_of     = { type = "array", elements = { type = "string" } } },
  { conditional     = {
      type = "record",
      fields = {
        { if_field = { type = "string" } },
        { if_match = { type = "record", fields = conditional_validators } },
        { then_field = { type = "string" } },
        { then_match = { type = "record", fields = conditional_validators } },
      },
    },
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

table.insert(field_schema, { entity_checks = entity_checks_schema })

local meta_errors = {
  ATTRIBUTE = "field of type '%s' cannot have attribute '%s'",
  REQUIRED = "field of type '%s' must declare '%s'",
  TABLE = "'%s' must be a table",
  TYPE = "missing type declaration",
  FIELDS_ARRAY = "each entry in fields must be a sub-table",
  FIELDS_KEY = "each key in fields must be a string",
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
  },
  len_eq = {
    ["array"]  = true,
    ["set"]    = true,
    ["hash"]   = true,
    ["string"] = true,
  },
  match = {
    ["string"] = true,
  },
  one_of = {
    ["string"] = true,
    ["number"] = true,
    ["integer"] = true,
  },
  timestamp = {
    ["integer"] = true,
  },
  uuid = {
    ["string"] = true,
  },
  unique = {
    ["string"] = true,
    ["number"] = true,
    ["integer"] = true,
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
    for _, required in ipairs(required_attributes[field.type]) do
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
      fields = {
        type = "array",
        elements = {
          type = "map",
          keys = { type = "string" },
          values = { type = "record", fields = field_schema },
          required = true,
          len_eq = 1,
        },
      },
    },
    {
      entity_checks = entity_checks_schema,
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
  },

  check = function(schema)
    local errors = {}

    if not schema.fields then
      errors["fields"] = meta_errors.TABLE:format("fields")
      return nil, errors
    end

    for _, item in ipairs(schema.fields) do
      if type(item) ~= "table" then
        errors["fields"] = meta_errors.FIELDS_ARRAY
        break
      end
      local k = next(item)
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


return MetaSchema

