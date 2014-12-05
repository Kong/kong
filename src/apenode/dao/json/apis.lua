-- Copyright (C) Mashape, Inc.

local constants = require "apenode.constants"
local BaseDao = require "apenode.dao.json.base_dao"

local Apis = {}
Apis.__index = Apis

setmetatable(Apis, {
  __index = BaseDao, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function Apis:_init()
  BaseDao._init(self, constants.APIS_COLLECTION) -- call the base class constructor
end

function Apis:get_by_host(host)
  if not host then return nil end

  for k,v in pairs(self:get_all()) do
    if v.public_dns == host then
      return v
    end
  end

  return nil
end

return Apis