-- Copyright (C) Mashape, Inc.

local constants = require "apenode.core.constants"
local BaseDao = require "apenode.dao.json.base_dao"

local Applications = {}
Applications.__index = Applications

setmetatable(Applications, {
  __index = BaseDao, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function Applications:_init()
  BaseDao._init(self, constants.APPLICATIONS_COLLECTION) -- call the base class constructor
end

function Applications:get_by_key(key)
  if not key then return nil end

  for k,v in pairs(self:get_all()) do
    if v.secret_key == key then
      return v
    end
  end

  return nil
end

function Applications:is_valid(application, api)
  if not application or not api then return false end

  -- TODO: implement

  return true
end

return Applications