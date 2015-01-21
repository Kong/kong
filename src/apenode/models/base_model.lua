-- Copyright (C) Mashape, Inc.

local rex = require "rex_pcre"
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
    if not t[k] and v.default ~= nil then -- Set default value for the filed if given
      if type(v.default) == "function" then
        t[k] = v.default()
      else
        t[k] = v.default
      end
    elseif v.required and (t[k] == nil or t[k] == "") then -- Check required field is set
      errors = add_error(errors, k, k.." is required")
    elseif t[k] and not is_update and v.read_only then -- Check field is not read only
      errors = add_error(errors, k, k.." is read only")
    elseif t[k] and type(t[k]) ~= v.type then -- Check type of the field
      if not (v.type == "id" or v.type == "timestamp") then
        errors = add_error(errors, k, k.." should be a "..v.type)
      end
    elseif v.func then -- Check field against a function
      local success, err = v.func(t[k], t, self._dao_factory)
      if not success then
        errors = add_error(errors, k, err)
      end
    end

    -- Check field against a regex
    if t[k] and v.regex then
      if not rex.match(t[k], v.regex) then
        errors = add_error(errors, k, k.." has an invalid value")
      end
    end

    -- Check if field's value is unique
    if t[k] and v.unique and not is_update then
      local data, err = self._find_one({[k] = t[k]}, self._dao)
      if data ~= nil then
        errors = add_error(errors, k, k.." with value ".."\""..t[k].."\"".." already exists")
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
      errors = add_error(errors, k, k.." is an unknown field")
    end
  end

  if errors then
    result = nil
  end

  return result, errors
end

---------------
-- BaseModel --
---------------

function BaseModel:new(collection, schema, t, dao_factory)
  -- The collection needs to be declared before just in case
  -- the validator needs it for the "unique" check
  self._schema = schema
  self._collection = collection

  self._dao = dao_factory[collection]
  self._dao_factory = dao_factory

  -- Populate the new object with the same fields
  if not t then t = {} end
  for k,v in pairs(t) do
    self[k] = t[k]
  end

  self._t = t
end

function BaseModel:save()
  local res, err = self:_validate(self._schema, self._t, false)
  if not res then
    return nil, err
  else
    local data, err = self._dao:insert_or_update(self._t)
    return data, err
  end
end

function BaseModel:delete()
  local n_success, err = self._dao:delete_by_id(self._t.id)
  return n_success, err
end

function BaseModel:update()
  -- Check if there are updated fields
  for k,_ in pairs(self._t) do
    self._t[k] = self[k]
  end

  local res, err = self:_validate(self._schema, self._t, true)
  if not res then
    return nil, err
  else
    local data, err = self._dao:update(self._t)
    return data, err
  end
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
