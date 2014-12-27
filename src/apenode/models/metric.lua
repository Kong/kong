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

local Metric = BaseModel:extend()
Metric["_COLLECTION"] = COLLECTION
Metric["_SCHEMA"] = SCHEMA

function Metric:new(t)
  return Metric.super.new(self, COLLECTION, SCHEMA, t)
end

function Metric.find_one(args)
  return Metric.super._find_one(COLLECTION, args)
end

function Metric.find(args, page, size)
  return Metric.super._find(COLLECTION, args, page, size)
end

function Metric.find_and_delete(args)
  return Metric.super._find_and_delete(COLLECTION, args)
end

function Metric:insert_or_update(entity, where_keys)
  error("Metric: insert_or_update not supported")
end

return Metric
