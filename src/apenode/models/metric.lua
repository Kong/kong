-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local COLLECTION = "metrics"
local SCHEMA = {
  id = { type = "string", read_only = true },
  api_id = { type = "string", required = true },
  application_id = { type = "string", required = false },
  name = { type = "string", required = true },
  timestamp = { type = "number", required = true },
  value = { type = "number", required = true }
}

local Metric = {
  _COLLECTION = COLLECTION,
  _SCHEMA = SCHEMA
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
  return BaseModel:_init(COLLECTION, t, SCHEMA)
end

function Metric.find_one(args)
  return BaseModel._find_one(COLLECTION, args)
end

function Metric.find(args, page, size)
  return BaseModel._find(COLLECTION, args, page, size)
end

function Metric.find_and_delete(args)
  return BaseModel._find_and_delete(COLLECTION, args)
end

function Metric:insert_or_update(entity, where_keys)
  error("Metric: insert_or_update not supported")
end

return Metric
