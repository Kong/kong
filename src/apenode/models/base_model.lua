-- Copyright (C) Mashape, Inc.

local rex = require("rex_pcre")
local Object = require "classic"

local BaseModel = Object:extend()

-------------
-- PRIVATE --
-------------

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

---------------
-- BaseModel --
---------------

function BaseModel:new(collection, schema, t, dao_factory)
  -- The collection needs to be declared before just in case
  -- the validator needs it for the "unique" check
  self._dao_factory = dao_factory
  self._collection = collection
  self._dao = dao_factory[collection]

  -- Validate the entity
  if not t then t = {} end
  local result, errors = self:_validate(schema, t)

  if errors then
    error(errors)
    --return nil, errors
  end

  for k,v in pairs(t) do
    self[k] = t[k]
  end

  self._t = result
end

-- Validate a table against a given schema
-- @param table schema A model schema to validate the entity against
-- @param table t A given entity to be validated against the schema
-- @param boolean is_update Ignores read_only fields during the validation if true
-- @return A filtered, valid table if success, nil if error
-- @return table A list of encountered errors during the validation
function BaseModel:_validate(schema, t, is_update)
  local result = {}
  local errors

  -- Check the given table against a given schema
  for k,v in pairs(schema) do
    -- Set default value for the filed if given
    if not t[k] and v.default ~= nil then
      t[k] = v.default
    -- Check required field is set
    elseif v.required and (t[k] == nil or t[k] == "") then
      errors = add_error(errors, k, k .. " is required")
    -- Check field is not read only
    elseif t[k] and not is_update and v.read_only then
      errors = add_error(errors, k, k .. " is read only")
    end
    -- Check type of the field
    if t[k] and type(t[k]) ~= v.type then
      errors = add_error(errors, k, k .. " should be a " .. v.type)
    end

    -- Check field against a regex
    if t[k] and v.regex then
      if not rex.match(t[k], v.regex) then
        errors = add_error(errors, k, k .. " has an invalid value")
      end
    end

    -- Check field against a function
    if v.func then
      local success, err = v.func(t[k], t, self._dao_factory)
      if not success then
        errors = add_error(errors, k, err)
      end
    end

    -- Check if field's value is unique
    if t[k] and v.unique then
      local data, err = self._find_one({[k] = t[k]}, self._collection, self._dao_factory)
      if data ~= nil then
        errors = add_error(errors, k, k .. " with value " .. "\"" .. t[k] .. "\"" .. " already exists")
      end
    end

    if t[k] and v.type == "table" then
      if v.schema_from_func then
        local table_schema, err = v.schema_from_func(t)
        if not table_schema then
          errors = add_error(errors, k, err)
        else
          local _, table_schema_err = BaseModel:_validate(table_schema, t[k], false)
          if table_schema_err then
            errors = add_error(errors, k, table_schema_err)
          end
        end
      end
    end

    result[k] = t[k]
  end

  -- Check for unexpected fields in the entity
  for k,v in pairs(t) do
    if not schema[k] then
      errors = add_error(errors, k, k .. " is an unknown field")
    end
  end

  if errors then
    result = nil
  end

  return result, errors
end

function BaseModel:save()
  local data, err = self._dao:insert_or_update(self._t)
  return data, err
end

function BaseModel:delete()
  local n_success, err = self._dao:delete(self._t.id)
  return n_success, err
end

function BaseModel:update()
  local res, err = self:_validate(self._SCHEMA, self._t, true)
  if not res then
    return nil, err
  else
    local data, err = self._dao:update(self._t)
    return data, err
  end
end

function BaseModel._delete_by_id(id, dao)
  local count, err = dao:delete_by_id(id)
  return count, err
end

function BaseModel._find_one(args, dao)
  local data, err = dao:find_one(args)
  return data, err
end

function BaseModel._find(args, page, size, dao)
  local data, total, err = dao:find(args, page, size)
  return data, total, err
end

return BaseModel
