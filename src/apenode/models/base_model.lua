-- Copyright (C) Mashape, Inc.

local Object = require "classic"
local Validator = require "apenode.models.validator"

local BaseModel = Object:extend()

function BaseModel:validate(update)
  return Validator.validate(self._t, self._schema, update, self._collection, self._dao_factory)
end

---------------
-- BaseModel --
---------------

function BaseModel:new(collection, schema, values, dao_factory)
  if not values then values = {} end

  self._schema = schema
  self._collection = collection
  self._dao = dao_factory[collection]
  self._dao_factory = dao_factory

  -- Populate the new object with the same fields
  for k,v in pairs(values) do
    self[k] = v
  end

  self._t = values
end

-- Save a model's values in database
-- @return {table} Values returned by the DAO's insert result
function BaseModel:save()
  local _, err = self:validate()
  if err then
    return nil, err
  else
    return self._dao:insert(self._t)
  end
end

-- Update a model's values in database
-- @return {number} Number of rows affected by the update
function BaseModel:update()
  -- Check if there are updated fields
  for k,_ in pairs(self._t) do
    if self[k] then
      self._t[k] = self[k]
    end
  end

  local _, err = self:validate(true)
  if err then
    return 0, err
  else
    return self._dao:update_by_id(self._t)
  end
end

-- Deletes a model from database
-- @return {boolean} Success of the deletion
function BaseModel:delete()
  return self._dao:delete_by_id(self._t.id)
end

function BaseModel._find_one(args, dao)
  return dao:find_one(args)
end

function BaseModel._find(args, page, size, dao)
  return dao:find(args, page, size)
end

return BaseModel
