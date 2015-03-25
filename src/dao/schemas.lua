local rex = require "rex_pcre"
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

--
-- Schemas
--
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

    -- Set default value for the filed if given
    if t[column] == nil and v.default ~= nil then
      if type(v.default) == "function" then
        t[column] = v.default()
      else
        t[column] = v.default
      end

    -- Check required fields are set
    elseif v.required and (t[column] == nil or t[column] == "") then
      errors = utils.add_error(errors, column, column.." is required")

    -- Check type if valid
    elseif v.type ~= nil and t[column] ~= nil and type(t[column]) ~= _M.get_type(v.type) and LUA_TYPES[v.type] then
      errors = utils.add_error(errors, column, column.." is not a "..v.type)

    -- Check type if value is allowed in the enum
    elseif v.enum and t[column] ~= nil then
      local found = false
      for _,allowed in ipairs(v.enum) do
        if allowed == t[column] then
          found = true
          break
        end
      end

      if not found then
        errors = utils.add_error(errors, column, string.format("\"%s\" is not allowed. Allowed values are: \"%s\"", t[column], table.concat(v.enum, "\", \"")))
      end

    -- Check field against a regex if specified
    elseif t[column] ~= nil and v.regex then
      if not rex.match(t[column], v.regex) then
        errors = utils.add_error(errors, column, column.." has an invalid value")
      end

    -- Check field against a custom function
    elseif v.func and type(v.func) == "function" then
      local ok, err = v.func(t[column], t)
      if not ok or err then
        errors = utils.add_error(errors, column, err)
      end

    -- is_update check immutability of a field
    elseif is_update and t[column] ~= nil and v.immutable and not v.required then
      errors = utils.add_error(errors, column, column.." cannot be updated")

    -- validate a subschema
    elseif t[column] ~= nil and v.schema then
      local sub_schema, err
      if type(v.schema) == "function" then
        sub_schema, err = v.schema(t)
      else
        sub_schema = v.schema
      end

      if err then
        -- could not retrieve sub schema
        errors = utils.add_error(errors, column, err)
      else
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

  -- Check for unexpected fields in the entity
  for k,v in pairs(t) do
    if schema[k] == nil then
      errors = utils.add_error(errors, k, k.." is an unknown field")
    end
  end

  return errors == nil, errors
end

return _M
