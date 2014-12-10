-- Copyright (C) Mashape, Inc.

local BaseDao = require "apenode.dao.cassandra.base_dao"

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

function Applications:get_by_key(public_key, secret_key)
  return nil
end

function Applications:get_by_account_id(account_id)
  local result = {}
  return result
end

function Applications:is_valid(application, api)
  if not application or not api then return false end

  -- TODO: implement

  return true
end

return Applications