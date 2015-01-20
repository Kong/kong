local BaseDao = require "apenode.dao.cassandra.base_dao"
local MetricModel = require "apenode.models.metric"

local Metrics = BaseDao:extend()

function Metrics:new(database, properties)
  Metrics.super.new(self, database, MetricModel._COLLECTION, MetricModel._SCHEMA, properties)
end

-- @override
function Metrics:insert_or_update()
  error("Metrics:insert_or_update() not supported")
end

function Metrics:increment(api_id, application_id, name, timestamp, step)
  local where_keys = {
    api_id = api_id,
    application_id = application_id,
    name = name,
    timestamp = timestamp
  }

  local _, _, where_values_to_bind = BaseDao._build_query_args(where_keys)
  local where = Metrics.super._build_where_field(where_keys)

  local query = [[ UPDATE ]]..MetricModel._COLLECTION..[[ SET value = value + ]]..tostring(step)..where

  local res, err = Metrics.super.query(self, query, where_values_to_bind)
  if err then
    return false, err
  end

  return true, nil
end

return Metrics
