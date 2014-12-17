-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local Metric = {
  _COLLECTION = "metrics",
  _SCHEMA = {
    api_id = { type = "string", required = true },
    application_id = { type = "string", required = false },
    name = { type = "string", required = true },
    timestamp = { type = "number", required = true },
    value = { type = "number", required = true }
  }
}

Metric.__index = Metric

setmetatable(Metric, {
  __index = BaseModel,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    return self:_init(...)
  end
})

function Metric:_init(t)
  return BaseModel:_init(Metric._COLLECTION, t, Metric._SCHEMA)
end

return Metric
