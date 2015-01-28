local rex = require "rex_pcre" -- Why? Lua has built in pattern which should do the job too

local _M = {}

local function add_error(errors, k, v)
  if not errors then errors = {} end

  if errors[k] then
    local list = {}
    table.insert(list, errors[k])
    table.insert(list, v)
    errors[k] = list
  else
    errors[k] = v
  end
  return errors
end

-- Validate a table against a given schema
-- @param {table} t Table to validate
-- @param {table} schema Schema against which to validate the table
-- @param {table} dao
-- @return {boolean} Success of validation
-- @return {table} A list of encountered errors during the validation
function _M.validate(t, schema)
  local errors = nil
  local schema_keys = {}

  -- Check the given table against a given schema
  for _,v in ipairs(schema) do
    local column = v._
    schema_keys[column] = true

    -- Set default value for the filed if given
    if not t[column] and v.default ~= nil then
      if type(v.default) == "function" then
        t[column] = v.default()
      else
        t[column] = v.default
      end
    -- Check required fields are set
    elseif v.required and (t[column] == nil or t[column] == "") then
      errors = add_error(errors, column, column.." is required")
    end

    -- Check field against a regex if specified
    if t[column] and v.regex then
      if not rex.match(t[column], v.regex) then
        errors = add_error(errors, column, column.." has an invalid value")
      end
    end
  end

  -- Check for unexpected fields in the entity
  for k,v in pairs(t) do
    if not schema_keys[k] then
      errors = add_error(errors, k, k.." is an unknown field")
    end
  end

  if errors then
    return false, errors
  else
    return true
  end
end

return _M
