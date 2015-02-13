local rex = require "rex_pcre" -- Why? Lua has built in pattern which should do the job too
local utils = require "kong.tools.utils"

--
-- Schemas
--
local _M = {}

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

    -- Check type if table
    elseif v.type == "table" and t[column] ~= nil and type(t[column]) ~= "table" then
      errors = utils.add_error(errors, column, column.." is not a table")

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
    elseif t[column] ~= nil and v.func and type(v.func) == "function" then
      local ok, err = v.func(t[column], t)
      if not ok or err then
        errors = utils.add_error(errors, column, err)
      end

    -- is_update check immutability of a field
    elseif is_update and t[column] ~= nil and v.immutable then
      errors = utils.add_error(errors, column, column.." cannot be updated")
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
