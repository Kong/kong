-- Copyright (C) Mashape, Inc.

local file_table = require "apenode.dao.json.file_table"
local uuid = require "uuid"
local cjson = require "cjson"

local BaseDao = {}
BaseDao.__index = BaseDao

setmetatable(BaseDao, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function BaseDao:_init(collection)
  self._data = file_table.init(collection)
end

function BaseDao:save(entity)
  entity.id = uuid()
  entity.created_at = ngx.now() * 1000
  self._data[entity.id] = entity
  return entity
end

function BaseDao:get_all()
  return self._data[nil]
end

function BaseDao:get_by_id(id)
  if id then
    return self._data[id]
  else
    return nil
  end
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