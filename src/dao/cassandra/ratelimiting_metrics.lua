local cassandra = require "cassandra"
local BaseDao = require "kong.dao.cassandra.base_dao"
local timestamp = require "kong.tools.timestamp"

local RateLimitingMetrics = BaseDao:extend()

function RateLimitingMetrics:new(properties)
  self._queries = {
    increment_counter = {
      query = [[ UPDATE ratelimiting_metrics SET value = value + 1 WHERE api_id = ? AND
                                                            identifier = ? AND
                                                            period_date = ? AND
                                                            period = ?; ]]
    },
    select_one = {
      query = [[ SELECT * FROM ratelimiting_metrics WHERE api_id = ? AND
                                             identifier = ? AND
                                             period_date = ? AND
                                             period = ?; ]]
    },
    delete = {
      query = [[ DELETE FROM ratelimiting_metrics WHERE api_id = ? AND
                                           identifier = ? AND
                                           period_date = ? AND
                                           period = ?; ]]
    }
  }

  RateLimitingMetrics.super.new(self, properties)
end

function RateLimitingMetrics:increment(api_id, identifier, current_timestamp)
  local periods = timestamp.get_timestamps(current_timestamp)
  local batch = cassandra.BatchStatement(cassandra.batch_types.COUNTER)

  for period, period_date in pairs(periods) do
    batch:add(self._statements.increment_counter.query, {
      cassandra.uuid(api_id),
      identifier,
      cassandra.timestamp(period_date),
      period
    })
  end

  return RateLimitingMetrics.super._execute(self, batch)
end

function RateLimitingMetrics:find_one(api_id, identifier, current_timestamp, period)
  local periods = timestamp.get_timestamps(current_timestamp)

  local metric, err = RateLimitingMetrics.super._execute(self, self._statements.select_one, {
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

function RateLimitingMetrics:delete(api_id, identifier, periods)
  error("ratelimiting_metrics:delete() not yet implemented")
end

-- Unsuported
function RateLimitingMetrics:insert()
  error("ratelimiting_metrics:insert() not supported")
end

function RateLimitingMetrics:update()
  error("ratelimiting_metrics:update() not supported")
end

function RateLimitingMetrics:find()
  error("ratelimiting_metrics:find() not supported")
end

function RateLimitingMetrics:find_by_keys()
  error("ratelimiting_metrics:find_by_keys() not supported")
end

return RateLimitingMetrics
