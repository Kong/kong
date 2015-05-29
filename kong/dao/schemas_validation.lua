local utils = require "kong.tools.utils"
local constants = require "kong.constants"

local LUA_TYPES = {
  boolean = true,
  string = true,
  number = true,
  table = true
}

local LUA_TYPE_ALIASES = {
  [constants.DATABASE_TYPES.ID] = "string",
  [constants.DATABASE_TYPES.TIMESTAMP] = "number"
}

local _M = {}

-- Returns the proper Lua type from a schema type, handling aliases
-- @param {string} type_val The type of the schema property
-- @return {string} A valid Lua type
function _M.get_type(type_val)
  local alias = LUA_TYPE_ALIASES[type_val]
  return alias and alias or type_val
end

-- Validate a table against a given schema
-- @param {table} t Table to validate
-- @param {table} schema Schema against which to validate the table
-- @param {boolean} is_update For an entity update, we might want a slightly different behaviour
-- @return {boolean} Success of validation
-- @return {table} A list of encountered errors during the validation
function _M.validate(t, schema, is_update)
  local errors

  -- Check the given table against a given schema
  for column, v in pairs(schema) do

    -- Set default value for the field if given
    if t[column] == nil and v.default ~= nil then
      if type(v.default) == "function" then
        t[column] = v.default(t)
      else
        t[column] = v.default
      end
    elseif is_update and t[column] ~= nil and v.immutable and not v.required then
      -- is_update check immutability of a field
      errors = utils.add_error(errors, column, column.." cannot be updated")
    end

    -- Check if type is valid boolean and numbers as strings are accepted and converted
    if v.type ~= nil and t[column] ~= nil then
      local valid
      if _M.get_type(v.type) == "number" and type(t[column]) == "string" then -- a number can also be sent as a string
        t[column] = tonumber(t[column])
        valid = t[column] ~= nil
      elseif _M.get_type(v.type) == "boolean" and type(t[column]) == "string" then
        local bool = t[column]:lower()
        valid = bool == "true" or bool == "false"
        t[column] = bool == "true"
      else
        valid = type(t[column]) == _M.get_type(v.type)
      end
      if not valid and LUA_TYPES[v.type] then
        errors = utils.add_error(errors, column, column.." is not a "..v.type)
      end
    end

    -- Check type if value is allowed in the enum
    if v.enum and t[column] ~= nil then
      local found = false
      for _, allowed in ipairs(v.enum) do
        if allowed == t[column] then
          found = true
          break
        end
      end

      if not found then
        errors = utils.add_error(errors, column, string.format("\"%s\" is not allowed. Allowed values are: \"%s\"", t[column], table.concat(v.enum, "\", \"")))
      end
    end

    -- Check field against a regex if specified
    if t[column] ~= nil and v.regex then
      if not ngx.re.match(t[column], v.regex) then
        errors = utils.add_error(errors, column, column.." has an invalid value")
      end
    end

    -- validate a subschema
    if v.schema then
      local sub_schema, err
      if type(v.schema) == "function" then
        sub_schema, err = v.schema(t)
      else
        sub_schema = v.schema
      end

      if err then
        -- could not retrieve sub schema
        errors = utils.add_error(errors, column, err)
      end

      if sub_schema then
        -- Check for sub-schema defaults and required properties
        for sub_field_k, sub_field in pairs(sub_schema) do
          if t[column] == nil then
            if sub_field.default then
              t[column] = {}
            elseif sub_field.required then -- only check required if field doesn't have a default
              errors = utils.add_error(errors, column, column.."."..sub_field_k.." is required")
            end
          end
        end

        if t[column] and type(t[column]) == "table" then
          -- validating subschema
          local s_ok, s_errors = _M.validate(t[column], sub_schema, is_update)
          if not s_ok then
            for s_k, s_v in pairs(s_errors) do
              errors = utils.add_error(errors, column.."."..s_k, s_v)
            end
          end
        end
      end
    end

    -- Check required fields are set
    if v.required and (t[column] == nil or t[column] == "") then
      errors = utils.add_error(errors, column, column.." is required")
    end

    -- Check field against a custom function only if there is no error on that field already
    if v.func and type(v.func) == "function" and (errors == nil or errors[column] == nil) then
      local ok, err, new_fields = v.func(t[column], t)
      if not ok and err then
        errors = utils.add_error(errors, column, err)
      elseif new_fields then
        for k, v in pairs(new_fields) do
          t[k] = v
        end
      end
    end
  end

  -- Check for unexpected fields in the entity
  for k, v in pairs(t) do
    if schema[k] == nil then
      errors = utils.add_error(errors, k, k.." is an unknown field")
    end
  end

  return errors == nil, errors
end

local digit = "[0-9a-f]"
local uuid_pattern = "^"..table.concat({ digit:rep(8), digit:rep(4), digit:rep(4), digit:rep(4), digit:rep(12) }, '%-').."$"
function _M.is_valid_uuid(uuid)
  return uuid and uuid:match(uuid_pattern) ~= nil
end

return _M
