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
-- @return {table} A filtered, valid table if success, nil if error
-- @return {table} A list of encountered errors during the validation
function _M.validate(t, schema, updating, collection, dao_factory)
  local result, errors = {}

  -- Check the given table against a given schema
  for k,v in pairs(schema) do
    -- Set default value for the filed if given
    if not t[k] and v.default ~= nil then
      if type(v.default) == "function" then
        t[k] = v.default()
      else
        t[k] = v.default
      end

    -- Check required fields are set
    elseif v.required and (t[k] == nil or t[k] == "") then
      errors = add_error(errors, k, k.." is required")

    -- Check we're not passing an id
    elseif not updating and t[k] and v.read_only then
      errors = add_error(errors, k, k.." is read only")

    -- Check types (number/string) of the field
    elseif v.type ~= "id" and v.type ~= "timestamp" and t[k] and type(t[k]) ~= v.type then
        errors = add_error(errors, k, k.." should be a "..v.type)

    -- Check field against a custom function
    elseif t[k] and v.func then
      local success, err = v.func(t[k], t, dao_factory)
      if not success then
        errors = add_error(errors, k, err)
      end
    end

    -- Check field against a regex if specified
    if t[k] and v.regex then
      if not rex.match(t[k], v.regex) then
        errors = add_error(errors, k, k.." has an invalid value")
      end
    end

    -- Check for unique properties
    if v.unique and t[k] and dao_factory ~= nil then
      local data, err = dao_factory[collection]:find_one { [k] = t[k] }
      if data ~= nil and data.id ~= t.id then
        errors = add_error(errors, k, k.." with value ".."\""..t[k].."\"".." already exists")
      elseif err then
        errors = add_error(errors, k, err)
      end
    end

    result[k] = t[k]
  end

  -- Check for unexpected fields in the entity
  for k,v in pairs(t) do
    if not schema[k] then
      errors = add_error(errors, k, k.." is an unknown field")
    end
  end

  if errors then
    result = nil
  end

  return result, errors
end

return _M
