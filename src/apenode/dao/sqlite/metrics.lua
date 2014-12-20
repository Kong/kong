local BaseDao = require "apenode.dao.sqlite.base_dao"
local MetricModel = require "apenode.models.metric"

local Metrics = BaseDao:extend()

function Metrics:new(database)
  Metrics.super:new(database, MetricModel._COLLECTION, MetricModel._SCHEMA)

  self.increment_stmt = database:prepare [[
    INSERT OR REPLACE INTO metrics
      VALUES (:api_id, :application_id, :name, :timestamp,
        COALESCE(
          (SELECT value FROM metrics
            WHERE api_id = :api_id
              AND application_id = :application_id
              AND name = :name
              AND timestamp = :timestamp),
        0) + :step);
  ]]
end

-- @override
function Metrics:insert_or_update(metric)
  error("Metrics:insert_or_update() not supported")
end

-- @override
function Metrics:delete(api_id, application_id, name, timestamp)
  self.delete_stmt:bind_values(api_id, application_id, name, timestamp)
  return self:exec_stmt(self.delete_stmt)
end

function Metrics:increment_metric(api_id, application_id, name, timestamp, step)
  if not step then step = 1 end

  self.increment_stmt:bind_names {
      name = name,
      step = step,
      value = value,
      api_id = api_id,
      timestamp = timestamp,
      application_id = application_id
  }
  local rowid, err = self:exec_stmt(self.insert_or_update_stmt)
  if err then
    return nil, err
  end

  self.get_by_rowid:bind_values(rowid)
  return self:exec_select_stmt(self.get_by_rowid)
end

return Metrics
