local rex = require "rex_pcre" -- Why? Lua has built in pattern which should do the job too
local utils = require "apenode.tools.utils"

--
-- Schemas
--
local _M = {}

-- Validate a table against a given schema
-- @param {table} t Table to validate
-- @param {table} schema Schema against which to validate the table
-- @param {table} dao
-- @return {boolean} Success of validation
-- @return {table} A list of encountered errors during the validation
function _M.validate(t, schema)
  local errors

  -- Check the given table against a given schema
  for column, v in pairs(schema) do

    -- Set default value for the filed if given
    if not t[column] and v.default ~= nil then
      if type(v.default) == "function" then
        t[column] = v.default()
      else
        t[column] = v.default
      end

    -- Check required fields are set
    elseif v.required and (t[column] == nil or t[column] == "") then
      errors = utils.add_error(errors, column, column.." is required")

    -- Check type if table
    elseif v.type == "table" and t[column] and type(t[column]) ~= "table" then
      errors = utils.add_error(errors, column, column.." is not a table")

    -- Check type if value is allowed in the enum
    elseif v.enum and t[column] then
      local found = false
      for _, c in ipairs(v.enum) do
        if c == t[column] then
          found = true
          break
        end
      end
      if not found then
        errors = utils.add_error(errors, column, "\""..t[column].."\" is not allowed. Allowed values are: \""..table.concat(v.enum, "\", \"").."\"")
      end

    -- Check field against a regex if specified
    elseif t[column] and v.regex then
      if not rex.match(t[column], v.regex) then
        errors = utils.add_error(errors, column, column.." has an invalid value")
      end
    end
  end

  -- Check for unexpected fields in the entity
  for k,v in pairs(t) do
    if not schema[k] then
      errors = utils.add_error(errors, k, k.." is an unknown field")
    end
  end

  return errors == nil, errors
end

return _M
