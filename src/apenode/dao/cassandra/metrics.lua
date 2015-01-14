local BaseDao = require "apenode.dao.cassandra.base_dao"
local MetricModel = require "apenode.models.metric"

local Metrics = BaseDao:extend()

function Metrics:new(client)
  Metrics.super.new(self, client, MetricModel._COLLECTION, MetricModel._SCHEMA)
end

-- @override
function Metrics:insert_or_update()
  error("Metrics:insert_or_update() not supported")
end

function Metrics:increment(api_id, application_id, name, timestamp, step)
  --TODO
end

return Metrics
