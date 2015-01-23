-- Copyright (C) Mashape, Inc.

local Object = require "classic"

local BaseModel = Object:extend()

-------------
-- PRIVATE --
-------------

function BaseModel:validate(is_update)

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
  local res, err = self:validate()
  if not res then
    return nil, err
  else
    local data, err = self._dao:insert_or_update(self._t)
    return data, err
  end
end

function BaseModel:update()
  -- Check if there are updated fields
  for k,_ in pairs(self._t) do
    self._t[k] = self[k]
  end

  local res, err = self:validate(self._t, true)
  if not res then
    return nil, err
  else
    local data, err = self._dao:update(self._t)
    return data, err
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
