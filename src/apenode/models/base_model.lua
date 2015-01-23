-- Copyright (C) Mashape, Inc.

local Object = require "classic"
local Validator = require "apenode.models.validator"

local BaseModel = Object:extend()

function BaseModel:validate()
  return Validator.validate(self._t, self._schema)
end

---------------
-- BaseModel --
---------------

function BaseModel:new(collection, schema, values, dao_factory)
  if not values then values = {} end

  self._schema = schema
  self._dao = dao_factory[collection]

  -- Populate the new object with the same fields
  for k,v in pairs(values) do
    self[k] = v
  end

  self._t = values
end

-- Save a model's values in database
-- @return {table} Values returned by the DAO's insert result
function BaseModel:save()
  local res, err = self:validate()
  if err then
    return nil, err
  end

  -- Check for unique properties
  for k, schema_field in pairs(self._schema) do
    if schema_field.unique and self._t[k] then
      local data, err = self._dao:find_one { [k] = self._t[k] }
      if data ~= nil then
        return nil, k.." with value ".."\""..self._t[k].."\"".." already exists"
      elseif err then
        return nil, err
      end
    end
  end

  if err then
    return nil, err
  else
    return self._dao:insert_or_update(self._t)
  end
end

-- Update a model's values in database
-- @return {table} Values returned by the DAO's update result
function BaseModel:update()
  -- Check if there are updated fields
  for k,_ in pairs(self._t) do
    self._t[k] = self[k]
  end

  local res, err = self:validate(self._t, true)
  if err then
    return nil, err
  else
    return self._dao:insert_or_update(self._t)
  end
end

function BaseModel:delete()
  local n_success, err = self._dao:delete_by_id(self._t.id)
  return n_success, err
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
