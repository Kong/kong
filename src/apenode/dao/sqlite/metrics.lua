local BaseDao = require "apenode.dao.sqlite.base_dao"
local MetricModel = require "apenode.models.metric"

local Metrics = BaseDao:extend()

function Metrics:new(database)
  Metrics.super.new(self, database, MetricModel._COLLECTION, MetricModel._SCHEMA)

  self.increment_stmt = Metrics.super.get_statement(self, [[
    INSERT OR REPLACE INTO metrics
      VALUES (:api_id, :application_id, :name, :timestamp,
        COALESCE(
          (SELECT value FROM metrics
            WHERE api_id = :api_id
              AND application_id = :application_id
              AND name = :name
              AND timestamp = :timestamp),
        0) + :step);
  ]])


  self.delete_stmt = Metrics.super.get_statement(self, [[
    DELETE FROM metrics WHERE api_id = :api_id
              AND application_id = :application_id
              AND name = :name
              AND timestamp = :timestamp;
  ]]);
end

-- @override
function Metrics:insert_or_update()
  error("Metrics:insert_or_update() not supported")
end

-- @override
function Metrics:find_one(args)
  return Metrics.super.find_one(self, {
    api_id = args.api_id,
    application_id = args.application_id,
    name = args.name,
    timestamp = args.timestamp
  })
end

-- @override
function Metrics:delete(api_id, application_id, name, timestamp)
  self.delete_stmt:bind_names {
    api_id = api_id,
    application_id = application_id,
    name = name,
    timestamp = timestamp
  }

  return self:exec_stmt_count_rows(self.delete_stmt)
end

function Metrics:increment(api_id, application_id, name, timestamp, step)
  if not step then step = 1 end

  self.increment_stmt:bind_names {
    api_id = api_id,
    application_id = application_id,
    name = name,
    timestamp = timestamp,
    step = step
  }

  local count, err = self:exec_stmt_count_rows(self.increment_stmt)
  if err then
    return nil, err
  end

  return self:find_one({
    api_id = api_id,
    application_id = application_id,
    name = name,
    timestamp = timestamp
    })
end

return Metrics
