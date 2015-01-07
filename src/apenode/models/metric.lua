-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local COLLECTION = "metrics"
local SCHEMA = {
  api_id = { type = "string", required = true },
  application_id = { type = "string", required = false },
  name = { type = "string", required = true },
  timestamp = { type = "number", required = true },
  value = { type = "number", required = true }
}

local Metric = BaseModel:extend()
Metric["_COLLECTION"] = COLLECTION
Metric["_SCHEMA"] = SCHEMA

function Metric:new(t, dao_factory)
  return Metric.super.new(self, COLLECTION, SCHEMA, t, dao_factory)
end

function Metric.find_one(args, dao_factory)
  return Metric.super._find_one(args, dao_factory[COLLECTION])
end

function Metric.find(args, page, size, dao_factory)
  return Metric.super._find(args, page, size, dao_factory[COLLECTION])
end

function Metric.increment(api_id, application_id, name, timestamp, step, dao_factory)
  return dao_factory[COLLECTION]:increment(api_id, application_id, name, timestamp, step)
end

function Metric.delete_by_id(id, dao_factory)
  return Metric.super._delete_by_id(id, dao_factory[COLLECTION])
end

function Metric:insert_or_update(entity, where_keys)
  error("Metric: insert_or_update not supported")
end

return Metric
