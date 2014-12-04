-- Copyright (C) Mashape, Inc.

local uuid = require "uuid"

local BaseDao = {}

function BaseDao:new()
  new_obj = { _data = {} }
  self.__index = self
  return setmetatable(new_obj, self)
end

function BaseDao:save(entity)
  entity.id = uuid()
  self._data[entity.id] = entity
  return entity
end

function BaseDao:get_all()
  local result = {}
  for k,v in pairs(self._data) do
      table.insert(result, v)
  end
  return result
end

function BaseDao:get_by_id(id)
  return self._data[id]
end

function BaseDao:delete(id)
  local item = self._data[id]
  self._data[id] = nil
  return item
end

function BaseDao:update(entity)
  self._data[entity.id] = entity
  return entity
end

return BaseDao