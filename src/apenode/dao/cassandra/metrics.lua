local BaseDao = require "apenode.dao.cassandra.base_dao"
local Client = require "apenode.dao.cassandra.client"
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

  local cmd_where_fields, cmd_where_values = Metrics.super._get_where_args({
    api_id = api_id,
    application_id = application_id,
    name = name,
    timestamp = timestamp
  })

  local cmd = "UPDATE "..MetricModel._COLLECTION.." SET value = value + "..tostring(step).." WHERE "..cmd_where_fields

  local res, err = Metrics.super.query(self, cmd, cmd_where_values)
  if err then
    return false, err
  end

  return true, nil
end

return Metrics
