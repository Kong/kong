local BaseDao = require "apenode.dao.sqlite.base_dao"
local MetricModel = require "apenode.models.metric"

local Metrics = BaseDao:extend()

function Metrics:new(database)
  Metrics.super.new(self, database, MetricModel._COLLECTION, MetricModel._SCHEMA)

  self.prepared_stmts = {}

  self.stmts = {
    increment = [[
      INSERT OR REPLACE INTO metrics
        VALUES (:api_id, :application_id, :name, :timestamp,
          COALESCE(
          (SELECT value FROM metrics WHERE api_id = :api_id
                                       AND application_id = :application_id
                                       AND name = :name
                                       AND timestamp = :timestamp),
          0) + :step
      );
    ]],
    delete = [[
      DELETE FROM metrics WHERE api_id = :api_id
                            AND application_id = :application_id
                            AND name = :name
                            AND timestamp = :timestamp;
    ]]
  }
end

function Metrics:prepare()
  for k,stmt in pairs(self.stmts) do
    self.prepared_stmts[k] = Metrics.super.get_statement(self, stmt)
  end
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
  self.prepared_stmts.delete:bind_names {
    api_id = api_id,
    application_id = application_id,
    name = name,
    timestamp = timestamp
  }

  return self:exec_stmt_count_rows(self.prepared_stmts.delete)
end

function Metrics:increment(api_id, application_id, name, timestamp, step)
  if not step then step = 1 end

  self.prepared_stmts.increment:bind_names {
    api_id = api_id,
    application_id = application_id,
    name = name,
    timestamp = timestamp,
    step = step
  }

  local count, err = self:exec_stmt_count_rows(self.prepared_stmts.increment)
  if err then
    return nil, err
  end

  return self:find_one {
    api_id = api_id,
    application_id = application_id,
    name = name,
    timestamp = timestamp
  }
end

return Metrics
