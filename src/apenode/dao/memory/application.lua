-- Copyright (C) Mashape, Inc.

local uuid = require "uuid"

local _M = {}
local data = {}

function _M.save(entity)
  entity.id = uuid()
  data[entity.id] = entity
  return entity
end

function _M.get_all()
  local result = {}
  for k,v in pairs(data) do
      table.insert(result, v)
  end
  return result
end

function _M.get_by_id(id)
  return data[id]
end

function _M.delete(id)
  local item = data[id]
  data[id] = nil
  return item
end

function _M.update(entity)
  data[entity.id] = entity
  return entity
end

return _M