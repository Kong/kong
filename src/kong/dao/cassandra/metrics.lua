local cassandra = require "cassandra"
local BaseDao = require "kong.dao.cassandra.base_dao"
local utils = require "kong.tools.utils"

local Metrics = BaseDao:extend()

function Metrics:new(database)
  self._queries = {
    increment_counter = {
      query = [[ UPDATE metrics SET value = value + 1 WHERE api_id = ? AND
                                                            identifier = ? AND
                                                            period_date = ? AND
                                                            period = ?; ]]
    },
    select_one = {
      query = [[ SELECT * FROM metrics WHERE api_id = ? AND
                                             identifier = ? AND
                                             period_date = ? AND
                                             period = ?; ]]
    },
    delete = {
      query = [[ DELETE FROM metrics WHERE api_id = ? AND
                                           identifier = ? AND
                                           period_date = ? AND
                                           period = ?; ]]
    }
  }

  Metrics.super.new(self, database)
end

function Metrics:increment(api_id, identifier, current_timestamp)
  local periods = utils.get_timestamps(current_timestamp)
  local batch = cassandra.BatchStatement(cassandra.batch_types.COUNTER)

  for period, period_date in pairs(periods) do
    batch:add(self._statements.increment_counter.query, {
      cassandra.uuid(api_id),
      identifier,
      cassandra.timestamp(period_date),
      period
    })
  end

  return Metrics.super._execute(self, batch)
end

function Metrics:find_one(api_id, identifier, current_timestamp, period)
  local periods = utils.get_timestamps(current_timestamp)

  local metric, err = Metrics.super._execute(self, self._statements.select_one, {
    cassandra.uuid(api_id),
    identifier,
    cassandra.timestamp(periods[period]),
    period
  })
  if err then
    return nil, err
  elseif #metric > 0 then
    metric = metric[1]
  else
    metric = nil
  end

  return metric
end

function Metrics:delete(api_id, identifier, periods)
  error("metrics:delete() not yet implemented")
end

-- Unsuported
function Metrics:insert()
  error("metrics:insert() not supported")
end

function Metrics:update()
  error("metrics:update() not supported")
end

function Metrics:find()
  error("metrics:find() not supported")
end

function Metrics:find_by_keys()
  error("metrics:find_by_keys() not supported")
end

return Metrics
