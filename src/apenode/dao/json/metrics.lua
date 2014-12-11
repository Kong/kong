-- Copyright (C) Mashape, Inc.

local constants = require "apenode.constants"
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

function Metrics:increment_metric(api_id, account_id, name, value)

end

function Metrics:retrive_metric(api_id, account_id, name)

end

return Metrics