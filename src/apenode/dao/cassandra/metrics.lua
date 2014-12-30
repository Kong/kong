local BaseDao = require "apenode.dao.cassandra.base_dao"
local MetricModel = require "apenode.models.metric"

local Metrics = BaseDao:extend()

function Metrics:new(configuration)
  Metrics.super.new(self, configuration, MetricModel._COLLECTION, MetricModel._SCHEMA)
end

-- @override
function Metrics:insert_or_update()
  error("Metrics:insert_or_update() not supported")
end

-- @override
function Metrics:find_one(api_id, application_id, name, timestamp)
  --TODO
end

-- @override
function Metrics:delete(api_id, application_id, name, timestamp)
  --TODO
end

function Metrics:increment_metric(api_id, application_id, name, timestamp, step)
  --TODO
end

return Metrics
