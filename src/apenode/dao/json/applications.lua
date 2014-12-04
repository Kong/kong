-- Copyright (C) Mashape, Inc.

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
  BaseDao._init(self, "applications") -- call the base class constructor
end

function Applications:is_valid(application, api)
  if not application or not api then return false end

  return true
end

return Applications