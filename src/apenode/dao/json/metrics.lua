-- Copyright (C) Mashape, Inc.

local constants = require "apenode.core.constants"
local BaseDao = require "apenode.dao.json.base_dao"

local Metrics = {}
Metrics.__index = Metrics

setmetatable(Metrics, {
  __index = BaseDao, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function Metrics:_init()
  BaseDao._init(self, constants.METRICS_COLLECTION) -- call the base class constructor
end

return Metrics