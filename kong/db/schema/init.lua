local tablex       = require "pl.tablex"
local pretty       = require "pl.pretty"
local utils        = require "kong.tools.utils"
local cjson        = require "cjson"


local setmetatable = setmetatable
local re_find      = ngx.re.find
local concat       = table.concat
local insert       = table.insert
local assert       = assert
local ipairs       = ipairs
local pairs        = pairs
local pcall        = pcall
local floor        = math.floor
local type         = type
local next         = next
local ngx_time     = ngx.time
local ngx_now      = ngx.now
local null         = ngx.null
local max          = math.max
local sub          = string.sub


local Schema       = {}
Schema.__index     = Schema


local validation_errors = {
  -- general message
  ERROR                     = "Validation error: %s",
  -- types
  ARRAY                     = "expected an array",
  SET                       = "expected a set",
  MAP                       = "expected a map",
  RECORD                    = "expected a record",
  STRING                    = "expected a string",
  NUMBER                    = "expected a number",
  BOOLEAN                   = "expected a boolean",
  INTEGER                   = "expected an integer",
  FUNCTION                  = "expected a function",
  -- validations
  EQ                        = "value must be %s",
  BETWEEN                   = "value should be between %d and %d",
  LEN_EQ                    = "length must be %d",
  LEN_MIN                   = "length must be at least %d",
  LEN_MAX                   = "length must be at most %d",
  MATCH                     = "invalid value: %s",
  NOT_MATCH                 = "invalid value: %s",
  MATCH_ALL                 = "invalid value: %s",
  MATCH_NONE                = "invalid value: %s",
  MATCH_ANY                 = "invalid value: %s",
  STARTS_WITH               = "should start with: %s",
  ONE_OF                    = "expected one of: %s",
  TIMESTAMP                 = "expected a valid timestamp",
  UUID                      = "expected a valid UUID",
  VALIDATION                = "failed validating: %s",
  -- field presence
  NOT_NULLABLE              = "field is not nullable",
  BAD_INPUT                 = "expected an input table",
  REQUIRED                  = "required field missing",
  NO_FOREIGN_DEFAULT        = "will not generate a default value for a foreign field",
  UNKNOWN                   = "unknown field",
  -- entity checks
  REQUIRED_FOR_ENTITY_CHECK = "field required for entity check",
  ENTITY_CHECK              = "failed entity check: %s(%s)",
  ENTITY_CHECK_N_FIELDS     = "entity check requires %d fields",
  CHECK                     = "entity check failed",
  CONDITIONAL               = "failed conditional validation",
  AT_LEAST_ONE_OF           = "at least one of these fields must be non-empty: %s",
  ONLY_ONE_OF               = "only one of these fields must be non-empty: %s",
  DISTINCT                  = "values of these fields must be distinct: %s",
  -- schema error
  SCHEMA_NO_DEFINITION      = "expected a definition table",
  SCHEMA_NO_FIELDS          = "error in schema definition: no 'fields' table",
  SCHEMA_MISSING_ATTRIBUTE  = "error in schema definition: missing attribute %s",
  SCHEMA_BAD_REFERENCE      = "schema refers to an invalid foreign entity: %s",
  SCHEMA_TYPE               = "invalid type: %s",
  -- primary key errors
  NOT_PK                    = "not a primary key",
  MISSING_PK                = "missing primary key",
  -- subschemas
  SUBSCHEMA_UNKNOWN         = "unknown type: %s",
  SUBSCHEMA_BAD_PARENT      = "entities of type '%s' cannot have subschemas",
  SUBSCHEMA_UNDEFINED_FIELD = "error in schema definition: abstract field was not specialized",
  SUBSCHEMA_BAD_TYPE        = "error in schema definition: cannot change type in a specialized field",
}


Schema.valid_types = {
  array   = true,
  set     = true,
  string  = true,
  number  = true,
  boolean = true,
  integer = true,
  foreign = true,
  map     = true,
  record  = true,
}


local uuid_regex = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"


local function make_length_validator(err, fn)
  return function(value, n, field)
    local len = #value
    if field.type == "map" then
      for _ in pairs(value) do
        len = len + 1
      end
    end
    if fn(len, n) then
      return true
    end
    return nil, validation_errors[err]:format(n)
  end
end


--- Validator functions available for schemas.
-- A validator can only affect one field.
-- Each validation is registered in a schema field definition as
-- a key-value pair. The key is the validation name and the value
-- is an optional argument (by convention, `true` if the argument
-- is to be ignored). Each validation function takes as inputs
-- the value to be validated and the argument given in the schema
-- definition. The function should return true or nil,
-- optionally followed by an error message. If the error message
-- is not given, the validation name (in uppercase) is used as
-- a key in `validation_errors` to get a message. If it was not
-- registered, a generic fallback error message is produced with
-- `validation_errors.VALIDATION`.
Schema.validators = {

  between = function(value, limits)
    if value < limits[1] or value > limits[2] then
      return nil, validation_errors.BETWEEN:format(limits[1], limits[2])
    end
    return true
  end,

  eq = function(value, wanted)
    if value == wanted then
      return true
    end
    local str = (wanted == null) and "null" or tostring(value)
    return nil, validation_errors.EQ:format(str)
  end,

  len_eq = make_length_validator("LEN_EQ", function(len, n)
    return len == n
  end),

  len_min = make_length_validator("LEN_MIN", function(len, n)
    return len >= n
  end),

  len_max = make_length_validator("LEN_MAX", function(len, n)
    return len <= n
  end),

  match = function(value, pattern)
    local m = value:match(pattern)
    if not m then
      return nil, validation_errors.MATCH:format(value)
    end
    return true
  end,

  not_match = function(value, pattern)
    local m = value:match(pattern)
    if m then
      return nil, validation_errors.NOT_MATCH:format(value)
    end
    return true
  end,

  match_all = function(value, list)
    for i = 1, #list do
      local m = value:match(list[i].pattern)
      if not m then
        return nil, list[i].err
      end
    end
    return true
  end,

  match_none = function(value, list)
    for i = 1, #list do
      local m = value:match(list[i].pattern)
      if m then
        return nil, list[i].err
      end
    end
    return true
  end,

  match_any = function(value, arg)
    for _, pattern in ipairs(arg.patterns) do
      local m = value:match(pattern)
      if m then
        return true
      end
    end
    return nil, arg.err
  end,

  starts_with = function(value, expected)
    -- produces simpler error messages than 'match'
    if sub(value, 1, #expected) ~= expected then
      return nil, validation_errors.STARTS_WITH:format(expected)
    end
    return true
  end,

  one_of = function(value, options)
    for _, option in ipairs(options) do
      if value == option then
        return true
      end
    end
    return nil, validation_errors.ONE_OF:format(concat(options, ", "))
  end,

  timestamp = function(value)
    return value > 0 or nil
  end,

  uuid = function(value)
    if #value ~= 36 then
      return nil
    end
    return re_find(value, uuid_regex, "ioj") and true or nil
  end,

  custom_validator = function(value, fn)
    return fn(value)
  end

}


Schema.validators_order = {
  "eq",
  "one_of",

  -- type-dependent
  "timestamp",
  "uuid",
  "between",

  -- strings (1/2)
  "len_eq",
  "len_min",
  "len_max",

  -- strings (2/2)
  "starts_with",
  "not_match",
  "match_none",
  "match",
  "match_all",
  "match_any",

  -- other
  "custom_validator",
}


--- Returns true if a field is non-empty (with emptiness defined
-- for strings and aggregate values).
-- This function is defined as `is_nonempty` rather than the more intuitive
-- `is_empty` because the former has a less fuzzy definition:
-- being non-empty clearly excludes null and nil values.
-- @param value a value, which may be `ngx.null` or `nil`.
local function is_nonempty(value)
  if value == nil
     or value == null
     or (type(value) == "table" and not next(value))
     or (type(value) == "string" and value == "") then
    return false
  end

  return true
end


--- Returns true if a table is a sequence
-- @param t a table to be checked
-- @return `true` if `t` is a sequence, otherwise returns false.
local function is_sequence(t)
  if type(t) ~= "table" then
    return false
  end

  local m, c = 0, 0

  for k, _ in pairs(t) do
    c = c + 1

    if t[c] == nil then
      return false
    end

    if type(k) ~= "number" or k < 0 or floor(k) ~= k then
      return false
    end

    m = max(m, k)
  end

  return c == m
end


--- Produce a nicely quoted list:
-- Given `{"foo", "bar", "baz"}` and `"or"`, produces
-- `"'foo', 'bar', 'baz'"`.
-- @param words an array of strings.
-- @return The string of quoted words.
local function quoted_list(words)
  local msg = {}
  for _, word in ipairs(words) do
    insert(msg, ("'%s'"):format(word))
  end
  return concat(msg, ", ")
end


local function merge_field(base, overrides)
  local field = {}
  for k,v in pairs(base) do
    field[k] = v
  end
  for k,v in pairs(overrides) do
    field[k] = v
  end
  return field
end


--- Entity checkers are cross-field validation rules.
-- An entity checker is implemented as an entry in this table,
-- containing a mandatory field `fn`, the checker function,
-- and an optional field `field_sources`.
--
-- An entity checker is used in a schema by adding an entry to
-- the `entity_checks` array of a schema table. Entries
-- in `entity_checks` are tables with a single key, named
-- after the entity checker; its value is the "entity check
-- argument". For example:
--
--     entity_checks = {
--        { only_one_of = { "field_a", "field_b" } },
--     },
--
-- The `fn` function which implements an entity checker receives
-- three arguments: a projection of the entity containing only
-- the relevant fields to this checker, the entity check argument,
-- and the schema table. This ensures that the entity checker
-- does _not_ have access by default to the entire entity being
-- checked. This allows us to enable/disable entity checkers on
-- partial updates.
--
-- To specify which fields are relevant to this checker, one
-- uses the `field_sources`. It is an array of strings, which
-- are key names to the entity check argument (see the `conditional`
-- entity checker for an example of its use).
-- If `field_sources` is not present, it is assumed that the
-- entity check argument is an array of field names, and that
-- all of them need to be present for the entity checker to run.
-- (this is the case, for example, of `only_one_of` in the example
-- above: this checker forces both fields to be given, and the
-- implementation of the checker will demand that only one is
-- non-empty).
Schema.entity_checkers = {

  at_least_one_of = {
    run_with_missing_fields = true,
    fn = function(entity, field_names)
      for _, name in ipairs(field_names) do
        if is_nonempty(entity[name]) then
          return true
        end
      end

      return nil, quoted_list(field_names)
    end,
  },

  only_one_of = {
    fn = function(entity, field_names)
      local found = false
      local ok = false
      for _, name in ipairs(field_names) do
        if is_nonempty(entity[name]) then
          if not found then
            found = true
            ok = true
          else
            ok = false
          end
        end
      end

      if ok then
        return true
      end
      return nil, quoted_list(field_names)
    end,
  },

  distinct = {
    fn = function(entity, field_names)
      local seen = {}
      for _, name in ipairs(field_names) do
        if is_nonempty(entity[name]) then
          if seen[entity[name]] then
            return nil, quoted_list(field_names)
          end
          seen[entity[name]] = true
        end
      end
      return true
    end,
  },

  --- Conditional validation: if the first field passes the given validator,
  -- then run the validator against the second field.
  -- Example:
  -- ```
  -- conditional = { if_field = "policy",
  --                 if_match = { match = "^redis$" },
  --                 then_field = "redis_host",
  --                 then_match = { required = true } }
  -- ```
  conditional = {
    field_sources = { "if_field", "then_field" },
    fn = function(entity, arg, schema)
      local if_value = entity[arg.if_field]
      local then_value = entity[arg.then_field]

      local if_merged = merge_field(schema.fields[arg.if_field], arg.if_match)
      local ok, _ = Schema.validate_field(schema, if_merged, if_value)
      if not ok then
        return true
      end

      -- Handle `required`
      if arg.then_match.required == true and then_value == null then
        local field_errors = { [arg.then_field] = validation_errors.REQUIRED }
        return nil, validation_errors.CONDITIONAL, field_errors
      end

      local then_merged = merge_field(schema.fields[arg.then_field], arg.then_match)
      local err
      ok, err = Schema.validate_field(schema, then_merged, then_value)
      if not ok then
        local field_errors = { [arg.then_field] = err }
        return nil, validation_errors.CONDITIONAL, field_errors
      end

      return true
    end,
  },

}


local function memoize(fn)
  local cache = setmetatable({}, { __mode = "k" })
  return function(k)
    if cache[k] then
      return cache[k]
    end
    local v = fn(k)
    cache[k] = v
    return v
  end
end


local get_field_schema = memoize(function(field)
  return Schema.new(field)
end)


-- Forward declaration
local validate_fields


--- Validate the field according to the schema.
-- For aggregate values, validate each field recursively.
-- @param self The complete schema object.
-- @param field The schema definition for the field.
-- @param value The value to be checked (may be ngx.null).
-- @return true if the field validates correctly;
-- nil and an error message on failure.
function Schema:validate_field(field, value)

  if value == null then
    if field.nullable == false then
      return nil, validation_errors.NOT_NULLABLE
    else
      return true
    end
  end

  if field.abstract == true then
    return nil, validation_errors.SUBSCHEMA_UNDEFINED_FIELD
  end

  if field.type == "array" then
    if not is_sequence(value) then
      return nil, validation_errors.ARRAY
    end
    if not field.elements then
      return nil, validation_errors.SCHEMA_MISSING_ATTRIBUTE:format("elements")
    end

    field.elements.nullable = false
    for _, v in ipairs(value) do
      local ok, err = self:validate_field(field.elements, v)
      if not ok then
        return nil, err
      end
    end

    for k, _ in pairs(value) do
      if type(k) ~= "number" then
        return nil, validation_errors.ARRAY
      end
    end

  elseif field.type == "set" then
    if not is_sequence(value) then
      return nil, validation_errors.SET
    end
    if not field.elements then
      return nil, validation_errors.SCHEMA_MISSING_ATTRIBUTE:format("elements")
    end

    field.elements.nullable = false
    local set = {}
    for _, v in ipairs(value) do
      if not set[v] then
        local ok, err = self:validate_field(field.elements, v)
        if not ok then
          return nil, err
        end
        set[v] = true
      end
    end

  elseif field.type == "map" then
    if type(value) ~= "table" then
      return nil, validation_errors.MAP
    end
    if not field.keys then
      return nil, validation_errors.SCHEMA_MISSING_ATTRIBUTE:format("keys")
    end
    if not field.values then
      return nil, validation_errors.SCHEMA_MISSING_ATTRIBUTE:format("values")
    end

    field.keys.nullable = false
    field.values.nullable = false
    for k, v in pairs(value) do
      local ok, err
      ok, err = self:validate_field(field.keys, k)
      if not ok then
        return nil, err
      end
      ok, err = self:validate_field(field.values, v)
      if not ok then
        return nil, err
      end
    end

  elseif field.type == "record" then
    if type(value) ~= "table" then
      return nil, validation_errors.RECORD
    end
    if not field.fields then
      return nil, validation_errors.SCHEMA_MISSING_ATTRIBUTE:format("fields")
    end

    local field_schema = get_field_schema(field)
    -- TODO return nested table or string?
    local copy = field_schema:process_auto_fields(value, "insert")
    local ok, err = field_schema:validate(copy)
    if not ok then
      return nil, err
    end

  elseif field.type == "foreign" then
    local ok, errs = field.schema:validate_primary_key(value, true)
    if not ok then
      -- TODO check with GUI team if they need prefer information
      -- of failed components of a compound foreign key
      -- as a nested table or just as a flat string.
      return nil, errs
    end

  elseif field.type == "integer" then
    if not (type(value) == "number"
       and value == floor(value)
       and value ~= 1/0
       and value ~= -1/0) then
      return nil, validation_errors.INTEGER
    end

  elseif field.type == "string" then
    if type(value) ~= "string" then
      return nil, validation_errors.STRING
    end
    -- empty strings are not accepted by default
    if not field.len_min then
      field.len_min = 1
    end

  elseif field.type == "function" then
    -- TODO: this type should only be used/visible from the
    -- metachema to validate the 'custom_validator'
    if type(value) ~= "function" then
      return nil, validation_errors.FUNCTION
    end

  elseif self.valid_types[field.type] then
    if type(value) ~= field.type then
      return nil, validation_errors[field.type:upper()]
    end

  else
    return nil, validation_errors.SCHEMA_TYPE:format(field.type)
  end

  for _, k in ipairs(Schema.validators_order) do
    if field[k] then
      local ok, err = self.validators[k](value, field[k], field)
      if not ok then
        return nil, err
                    or validation_errors[k:upper()]
                    or validation_errors.VALIDATION:format(k)
      end
    end
  end

  return true
end


--- Produce a default value for a given field.
-- @param field The field definition table.
-- @return A default value. All fields are nullable by default and return
-- `ngx.null`, unless explicitly configured not to with `nullable = false`,
-- in which case they return a type-specific default.
-- If a default value cannot be produced (due to circumstances that
-- will produce errors later on validation), it simply returns `nil`.
local function default_value(field)
  if field.abstract then
    return nil
  end

  if field.nullable ~= false then
    return null
  end

  if field.type == "record" then
    local field_schema = get_field_schema(field)
    return field_schema:process_auto_fields({}, "insert")
  elseif field.type == "array" or field.type == "set"
     or field.type == "map" then
    return {}
  elseif field.type == "number" or field.type == "integer" then
    return 0
  elseif field.type == "boolean" then
    return false
  elseif field.type == "string" then
    return ""
  end
  -- For cases that will produce a validation error, just return nil
  return nil
end

--- Merge the contents of a table into another. Numeric keys
-- are appended sequentially, string keys take over their slots.
-- For example:
-- `merge_into_table({ [1] = 2, a = 3 }, { [1] = 4, a = 5, b = 6 }`
-- produces `{ [1] = 2, [2] = 4, a = 5, b = 6 }`
-- @param dst The destination table
-- @param src The source table
local function merge_into_table(dst, src)
  for k,v in pairs(src) do
    if type(k) == "number" then
      insert(dst, v)
    else
      dst[k] = v
    end
  end
end


--- Given missing field named `k`, with definition `field`,
-- fill its slot in `entity` with an appropriate default value,
-- if possible.
-- @param k The field name.
-- @param field The field definition table.
-- @param entity The entity object where key `k` is missing.
local function handle_missing_field(k, field, entity)
  if field.default ~= nil then
    entity[k] = tablex.deepcopy(field.default)
    return
  end

  -- If `required`, it will fail later.
  -- If `nilable` (metaschema only), a default value is not necessary.
  if field.required or field.nilable then
    return
  end

  entity[k] = default_value(field)
end


--- Check if subschema field is compatible with the abstract field it replaces.
-- @return true if compatible, false otherwise.
local function compatible_fields(f1, f2)
  local t1, t2 = f1.type, f2.type
  if t1 ~= t2 then
    return false
  end
  if t1 == "record" then
    return true
  end
  if t1 == "array" or t1 == "set" then
    return f1.elements.type == f2.elements.type
  end
  if t1 == "array" or t1 == "set" then
    return f1.elements.type == f2.elements.type
  end
  if t1 == "map" then
    return f1.keys.type == f2.keys.type and f1.values.type == f2.values.type
  end
  return true
end


local function get_subschema_fields(self, input)
  if self.subschemas and self.subschema_key then
    local subschema = self.subschemas[input[self.subschema_key]]
    if subschema then
      return self.subschemas[input[self.subschema_key]].fields
    end
  end
  return nil
end


local function resolve_field(self, k, field, subschema_fields)
  field = field or self.fields[k]
  if not field then
    return nil, validation_errors.UNKNOWN
  end
  if subschema_fields then
    local ss_field = subschema_fields[k]
    if ss_field then
      if not compatible_fields(field, ss_field) then
        return nil, validation_errors.SUBSCHEMA_BAD_TYPE
      end
      field = ss_field
    end
  end
  return field
end


--- Validate fields of a table, individually, against the schema.
-- @param self The schema
-- @param input The input table.
-- @return Two arguments: the first is true on success and nil on failure.
-- The second is a table containing all errors, indexed numerically for
-- general errors, and by field name for field errors.
-- In all cases, the input table is untouched.
validate_fields = function(self, input)
  assert(type(input) == "table", validation_errors.BAD_INPUT)

  local errors, _ = {}

  local subschema_fields = get_subschema_fields(self, input)

  for k, v in pairs(input) do
    local err
    local field = self.fields[k]
    if field and field.type == "self" then
      field = input
    else
      field, err = resolve_field(self, k, field, subschema_fields)
    end
    if field then
      _, errors[k] = self:validate_field(field, v)
    else
      errors[k] = err
    end
  end

  if next(errors) then
    return nil, errors
  end
  return true, errors
end


--- Runs an entity check, making sure it has access to all fields it asked for,
-- and that it only has access to the fields it asked for.
-- It will call `self.entity_checkers[name]` giving it a subset of `input`,
-- based on the list of fields given at `schema.entity_checks[name].fields`.
-- @param self The schema table
-- @param name The name of the entity check
-- @param input The whole input entity.
-- @param arg The argument table of the entity check declaration
-- @return True on success, or nil followed by an error message and a table
-- of field-specific errors.
local function run_entity_check(self, name, input, arg)
  local ok = true
  local check_input = {}
  local field_errors = {}
  local checker = self.entity_checkers[name]
  local fields_to_check = {}

  if checker.field_sources then
    for _, source in ipairs(checker.field_sources) do
      local v = arg[source]
      if type(v) == "string" then
        insert(fields_to_check, v)
      elseif type(v) == "table" then
        for _, fname in ipairs(v) do
          insert(fields_to_check, fname)
        end
      end
    end
  else
    fields_to_check = arg
  end

  local all_nil = true
  for _, fname in ipairs(fields_to_check) do
    if input[fname] == nil then
      if not checker.run_with_missing_fields then
        local err = validation_errors.REQUIRED_FOR_ENTITY_CHECK
        field_errors[fname] = err
        ok = false
      end
    else
      all_nil = false
    end
    check_input[fname] = input[fname]
  end
  -- Don't run check if none of the fields are present (update)
  if all_nil then
    return true
  end

  if not ok then
    return nil, nil, field_errors
  end

  local err
  ok, err, field_errors = checker.fn(check_input, arg, self)
  if ok then
    return true
  end

  err = validation_errors[name:upper()]:format(err)
  if not err then
    local data = pretty.write({ name = arg }):gsub("%s+", " ")
    err = validation_errors.ENTITY_CHECK:format(name, data)
  end
  return nil, err, field_errors
end


--- Runs the schema's custom `self.check()` function.
-- It requires the full entity to be present.
-- TODO hopefully deprecate this function.
-- @param self The schema table
-- @param name The name of the entity check
-- @param entity_errors The current array of entity errors.
-- @param field_errors The current table of accumulated field errors.
-- the array with check errors if any
local function run_self_check(self, input, entity_errors, field_errors)
  local ok = true
  for fname, field in self:each_field() do
    if input[fname] == nil and not field.nilable then
      local err = validation_errors.REQUIRED_FOR_ENTITY_CHECK:format(fname)
      field_errors[fname] = err
      ok = false
    end
  end

  if not ok then
    return nil
  end

  local err
  ok, err = self.check(input)
  if ok then
    return
  end

  if type(err) == "string" then
    insert(entity_errors, err)

  elseif type(err) == "table" then
    for k, v in pairs(err) do
      if type(k) == "number" then
        insert(entity_errors, v)
      else
        field_errors[k] = v
      end
    end

  else
    insert(entity_errors, validation_errors.CHECK)
  end
end


--- Run entity checks over the whole table.
-- This includes the custom `check` function.
-- In case of any errors, add them to the errors table.
-- @param self The schema
-- @param input The input table.
-- @return True on success; nil, the table of entity check errors
-- (where keys are the entity check names with string values or
-- "check" and an array of self-check error strings)
-- and the table of field errors otherwise.
local function run_entity_checks(self, input)
  local entity_errors = {}
  local field_errors = {}

  if self.entity_checks then
    for _, check in ipairs(self.entity_checks) do
      local check_name = next(check)
      local _, err, f_errs = run_entity_check(self, check_name, input, check[check_name])
      insert(entity_errors, err)
      if f_errs then
        merge_into_table(field_errors, f_errs)
      end
    end
  end

  if self.check then
    run_self_check(self, input, entity_errors, field_errors)
  end

  if next(entity_errors) or next(field_errors) then
    return nil, entity_errors, field_errors
  end
  return true
end


--- Ensure that a given table contains only the primary-key
-- fields of the entity and that their fields validate.
-- @param pk A table with primary-key fields only.
-- @param ignore_others If true, the function will ignore non-primary key
-- entries.
-- @return True on success; nil, error message and error table otherwise.
function Schema:validate_primary_key(pk, ignore_others)
  local pk_set = {}
  local errors = {}

  for _, k in ipairs(self.primary_key) do
    pk_set[k] = true
    local field = self.fields[k]
    local v = pk[k]

    if not v then
      errors[k] = validation_errors.MISSING_PK

    elseif (field.required or field.auto) and v == null then
      errors[k] = validation_errors.REQUIRED

    else
      local _
      _, errors[k] = self:validate_field(field, v)
    end
  end

  if not ignore_others then
    for k, _ in pairs(pk) do
      if not pk_set[k] then
        errors[k] = validation_errors.NOT_PK
      end
    end
  end

  if next(errors) then
    return nil, errors
  end
  return true
end


local Set_mt = {
  __index = function(set, key)
    for i, val in ipairs(set) do
      if key == val then
        return i
      end
    end
  end
}


--- Sets (or replaces) metatable of an array:
-- 1. array is a proper sequence, but empty, `cjson.empty_array_mt`
--    will be used as a metatable of the returned array.
-- 2. otherwise no modifications are made to input parameter.
-- @param array The table containing an array for which to apply the metatable.
-- @return input table (with metatable, see above)
local function make_array(array)
  if is_sequence(array) and #array == 0 then
    return setmetatable(array, cjson.empty_array_mt)
  end

  return array
end


--- Sets (or replaces) metatable of a set and removes duplicates:
-- 1. set is a proper sequence, but empty, `cjson.empty_array_mt`
--    will be used as a metatable of the returned set.
-- 2. set a proper sequence, and has values, `Set_mt`
--    will be used as a metatable of the returned set.
-- 3. otherwise no modifications are made to input parameter.
-- @param set The table containing a set for which to apply the metatable.
-- @return input table (with metatable, see above)
local function make_set(set)
  if not is_sequence(set) then
    return set
  end

  local count = #set

  if count == 0 then
    return setmetatable(set, cjson.empty_array_mt)
  end

  local o = {}
  local s = {}
  local j = 0

  for i = 1, count do
    local v = set[i]
    if not s[v] then
      j = j + 1
      o[j] = v
      s[v] = true
    end
  end

  return setmetatable(o, Set_mt)
end


--- Given a table, update its fields whose schema
-- definition declares them as `auto = true`,
-- based on its CRUD operation context, and set
-- defaults for missing values when the CRUD context
-- is "insert".
-- This function encapsulates various "smart behaviors"
-- for value creation and update.
-- @param input The table containing data to be processed.
-- @param context a string describing the CRUD context:
-- valid values are: "insert", "update"
-- @param nulls boolean: return nulls as explicit ngx.null values
-- @return A new table, with the auto fields containing
-- appropriate updated values.
function Schema:process_auto_fields(input, context, nulls)
  local output = tablex.deepcopy(input)
  local now_s  = ngx_time()
  local now_ms = ngx_now()

  for key, field in self:each_field(input) do
    if field.auto then
      if field.uuid and context == "insert" then
        output[key] = utils.uuid()
      elseif field.uuid and context == "upsert" and output[key] == nil then
        output[key] = utils.uuid()

      elseif (key == "created_at" and (context == "insert" or
                                       context == "upsert")) or
             (key == "updated_at" and (context == "insert" or
                                       context == "upsert" or
                                       context == "update")) then

        if field.type == "number" then
          output[key] = now_ms
        elseif field.type == "integer" then
          output[key] = now_s
        end
      end
    end

    local field_value = output[key]

    if field_value ~= nil then
      local field_type  = field.type
      if field_type == "array" then
        output[key] = make_array(field_value)
      elseif field_type == "set" then
        output[key] = make_set(field_value)
      elseif field_type == "record" and not field.abstract then
        if field_value ~= null then
          local field_schema = get_field_schema(field)
          output[key] = field_schema:process_auto_fields(field_value, context)
        end
      end

    elseif context ~= "update" then
      handle_missing_field(key, field, output)
    end

    if context == "select" and output[key] == null and not nulls then
      output[key] = nil
    end
  end

  return output
end


--- Validate a table against the schema, ensuring that the entity is complete.
-- It validates fields for their attributes,
-- and runs the global entity checks against the entire table.
-- @param input The input table.
-- @param full_check If true, demands entity table to be complete.
-- If false, accepts missing `required` fields when those are not
-- needed for global checks.
-- @return True on success.
-- On failure, it returns nil and a table containing all errors,
-- indexed by field name for field errors, plus an "@entity" key
-- containing entity-checker and self-check errors.
-- This is an example of what an error table looks like:
--  {
--     ["name"] = "...error message...",
--     ["service"] = {
--        ["id"] = "...error message...",
--     }
--     ["@entity"] = {
--       "error message from at_least_one_of",
--       "error message from other entity validators",
--       "first error message from self-check function",
--       "second error message from self-check function",
--     }
--  }
-- In all cases, the input table is untouched.
function Schema:validate(input, full_check)
  if full_check == nil then
    full_check = true
  end

  local ok, subschema_error
  if self.subschema_key then
    local key = input[self.subschema_key]
    if not (self.subschemas and self.subschemas[key]) then
      subschema_error = validation_errors.SUBSCHEMA_UNKNOWN:format(key)
    end
  end

  local _, field_errors = validate_fields(self, input)

  if subschema_error then
    field_errors[self.subschema_key] = subschema_error
  end

  for name, field in self:each_field() do
    if field.required
       and (input[name] == null
            or (full_check and input[name] == nil)) then
      field_errors[name] = validation_errors.REQUIRED
    end
  end

  local entity_errors, f_errs
  ok, entity_errors, f_errs = run_entity_checks(self, input)
  if not ok then
    if next(entity_errors) then
      field_errors["@entity"] = entity_errors
    end
    merge_into_table(field_errors, f_errs)
  end

  if next(field_errors) then
    return nil, field_errors
  end
  return true
end


--- Validate a table against the schema, ensuring that the entity is complete.
-- It validates fields for their attributes,
-- and runs the global entity checks against the entire table.
-- @param input The input table.
-- @return True on success.
-- On failure, it returns nil and a table containing all errors,
-- indexed numerically for general errors, and by field name for field errors.
-- In all cases, the input table is untouched.
function Schema:validate_insert(input)
  return self:validate(input, true)
end


-- Validate a table against the schema, accepting a partial entity.
-- It validates fields for their attributes, but accepts missing `required`
-- fields when those are not needed for global checks,
-- and runs the global checks against the entire table.
-- @param input The input table.
-- @return True on success.
-- On failure, it returns nil and a table containing all errors,
-- indexed numerically for general errors, and by field name for field errors.
-- In all cases, the input table is untouched.
function Schema:validate_update(input)

  -- Monkey-patch some error messages to make it clearer why they
  -- apply during an update. This avoids propagating update-awareness
  -- all the way down to the entity checkers (which would otherwise
  -- defeat the whole purpose of the mechanism).
  local rfec = validation_errors.REQUIRED_FOR_ENTITY_CHECK
  local aloo = validation_errors.AT_LEAST_ONE_OF
  validation_errors.REQUIRED_FOR_ENTITY_CHECK = rfec .. " when updating"
  validation_errors.AT_LEAST_ONE_OF = "when updating, " .. aloo

  local ok, err, err_t = self:validate(input, false)

  -- Restore the original error messages
  validation_errors.REQUIRED_FOR_ENTITY_CHECK = rfec
  validation_errors.AT_LEAST_ONE_OF = aloo

  return ok, err, err_t
end


--- Validate a table against the schema, ensuring that the entity is complete.
-- It validates fields for their attributes,
-- and runs the global entity checks against the entire table.
-- @param input The input table.
-- @return True on success.
-- On failure, it returns nil and a table containing all errors,
-- indexed numerically for general errors, and by field name for field errors.
-- In all cases, the input table is untouched.
function Schema:validate_upsert(input)
  return self:validate(input, true)
end


--- An iterator for schema fields.
-- Returns a function to be used in `for` loops,
-- which produces the key and the field table,
-- as in `for field_name, field_data in self:each_field() do`
-- @return the iteration function
function Schema:each_field(values)
  local i = 1

  local subschema_fields
  if values then
    subschema_fields = get_subschema_fields(self, values)
  end

  return function()
    local item = self.fields[i]
    if not self.fields[i] then
      return nil
    end
    local key = next(item)
    local field = resolve_field(self, key, item[key], subschema_fields)
    i = i + 1
    return key, field
  end
end


--- Produce a string error message based on the table of errors
-- produced by the `validate` function.
-- @param errors The table of errors.
-- @return A string representing the errors, or nil if there
-- were no errors or a table was not given.
function Schema:errors_to_string(errors)
  if not errors or type(errors) ~= "table" or not next(errors) then
    return nil
  end

  local msgs = {}

  -- General errors first
  if errors["@entity"] then
    for _, err in pairs(errors["@entity"]) do
      insert(msgs, err)
    end
  end

  for _, err in ipairs(errors) do
    insert(msgs, err)
  end

  -- Field-specific errors
  for k, err in pairs(errors) do
    if k ~= "@entity" then
      if type(err) == "table" then
        err = self:errors_to_string(err)
      end
      if type(k) == "string" then
        insert(msgs, k..": "..err)
      end
    end
  end

  local summary = concat(msgs, "; ")
  return validation_errors.ERROR:format(summary)
end


--- Given a field of type `"foreign"`, returns the schema object for it.
-- @param field A field definition table
-- @return A schema object, or nil and an error message.
local function get_foreign_schema_for_field(field)
  local ref = field.reference
  if not ref then
    return nil, validation_errors.SCHEMA_MISSING_ATTRIBUTE:format("reference")
  end

  -- TODO add support for non-core entities
  local pok, def = pcall(require, "kong.db.schema.entities." .. ref)
  if not (pok and def) then
    return nil, validation_errors.SCHEMA_BAD_REFERENCE:format(ref)
  end

  -- FIXME we really shouldn't be creating schema objects each
  -- time, but rather getting schema objects from the modules,
  -- instead of bare schema definition tables.
  return Schema.new(def)
end


--- Cycle-aware table copy.
-- To be replaced by tablex.deepcopy() when it supports cycles.
local function copy(t, cache)
  if type(t) ~= "table" then
    return t
  end
  cache = cache or {}
  if cache[t] then
    return cache[t]
  end
  local c = {}
  cache[t] = c
  for k, v in pairs(t) do
    local kk = copy(k, cache)
    local vv = copy(v, cache)
    c[kk] = vv
  end
  return c
end


--- Instatiate a new schema from a definition.
-- @param definition A table with attributes describing
-- fields and other information about a schema.
-- @return The object implementing the schema matching
-- the given definition.
function Schema.new(definition)
  if not definition then
    return nil, validation_errors.SCHEMA_NO_DEFINITION
  end

  if not definition.fields then
    return nil, validation_errors.SCHEMA_NO_FIELDS
  end

  local self = copy(definition)
  setmetatable(self, Schema)

  -- Also give access to fields by name
  for key, field in self:each_field() do
    self.fields[key] = field
    if field.type == "foreign" then
      local err
      field.schema, err = get_foreign_schema_for_field(field)
      if not field.schema then
        return nil, err
      end
    end
  end

  return self
end


function Schema.new_subschema(self, key, definition)
  assert(type(key) == "string", "key must be a string")
  assert(type(definition) == "table", "definition must be a table")

  if not self.subschema_key then
    return nil, validation_errors.SUBSCHEMA_BAD_PARENT:format(self.name)
  end

  local subschema, err = Schema.new(definition)
  if not subschema then
    return nil, err
  end

  if not self.subschemas then
    self.subschemas = {}
  end
  self.subschemas[key] = subschema

  return true
end


function Schema.define(tbl)
  return setmetatable(tbl, {
    __call = function(t, arg)
      arg = arg or {}
      for k,v in pairs(t) do
        if not arg[k] then
          arg[k] = v
        end
      end
      return arg
    end
  })
end


return Schema
