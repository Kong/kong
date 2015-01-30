local rex = require "rex_pcre" -- Why? Lua has built in pattern which should do the job too
local cjson = require "cjson"

--
-- Schema
--
local _M = {}

function _M.add_error(errors, k, v)
  if not errors then errors = {} end

  if errors and errors[k] then
    local list = {}
    table.insert(list, errors[k])
    table.insert(list, v)
    errors[k] = list
  else
    errors[k] = v
  end

  return errors
end

function _M.serialize(t, schema)
  if t then
    for k,v in pairs(schema) do
      if t[k] and v.type == "table" then
        t[k] = cjson.encode(t[k])
      end
    end
  end
  return t
end

function _M.deserialize(t, schema)
  if t then
    for k,v in pairs(schema) do
      if t[k] and v.type == "table" then
        t[k] = cjson.decode(t[k])
      elseif t[k] and v.type == "string" then
        t[k] = tostring(t[k])
      end
    end
  end
  return t
end

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
      errors = _M.add_error(errors, column, column.." is required")

    -- Check type if table
    elseif v.type == "table" and t[column] and type(t[column]) ~= "table" then
      errors = _M.add_error(errors, column, column.." is not a table")
    end

    -- Check field against a regex if specified
    if t[column] and v.regex then
      if not rex.match(t[column], v.regex) then
        errors = _M.add_error(errors, column, column.." has an invalid value")
      end
    end
  end

  -- Check for unexpected fields in the entity
  for k,v in pairs(t) do
    if not schema[k] then
      errors = _M.add_error(errors, k, k.." is an unknown field")
    end
  end

  return errors == nil, errors
end

return _M
