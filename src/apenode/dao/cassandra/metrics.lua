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

function Metrics:increment(api_id, application_id, origin_ip, name, timestamp, period, step)
  local where_keys = {
    api_id = api_id,
    application_id = application_id,
    origin_ip = origin_ip,
    name = name,
    period = period,
    timestamp = timestamp
  }

  local _, _, where_values_to_bind = Metrics.super._build_query_args(self, where_keys)
  local where = Metrics.super._build_where_fields(where_keys)

  local query = [[ UPDATE ]]..MetricModel._COLLECTION..[[ SET value = value + ]]..tostring(step)..where

  return self:_exec_stmt(query, where_values_to_bind)
end

return Metrics
