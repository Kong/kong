local cassandra = require "cassandra"
local BaseDao = require "kong.dao.cassandra.base_dao"
local timestamp = require "kong.tools.timestamp"

local ResponseRateLimitingMetrics = BaseDao:extend()

function ResponseRateLimitingMetrics:new(properties)
  self._table = "response_ratelimiting_metrics"
  self.queries = {
    increment_counter = [[ UPDATE response_ratelimiting_metrics SET value = value + ? WHERE api_id = ? AND
                            identifier = ? AND
                            period_date = ? AND
                            period = ?; ]],
    select_one = [[ SELECT * FROM response_ratelimiting_metrics WHERE api_id = ? AND
                      identifier = ? AND
                      period_date = ? AND
                      period = ?; ]],
    delete = [[ DELETE FROM response_ratelimiting_metrics WHERE api_id = ? AND
                  identifier = ? AND
                  period_date = ? AND
                  period = ?; ]]
  }

  ResponseRateLimitingMetrics.super.new(self, properties)
end

function ResponseRateLimitingMetrics:increment(api_id, identifier, current_timestamp, value, name)
  local periods = timestamp.get_timestamps(current_timestamp)
  local batch = cassandra:BatchStatement(cassandra.batch_types.COUNTER)

  for period, period_date in pairs(periods) do
    batch:add(self.queries.increment_counter, {
      cassandra.counter(value),
      cassandra.uuid(api_id),
      identifier,
      cassandra.timestamp(period_date),
      name.."_"..period
    })
  end

  return ResponseRateLimitingMetrics.super._execute(self, batch)
end

function ResponseRateLimitingMetrics:find_one(api_id, identifier, current_timestamp, period, name)
  local periods = timestamp.get_timestamps(current_timestamp)

  local metric, err = ResponseRateLimitingMetrics.super._execute(self, self.queries.select_one, {
    cassandra.uuid(api_id),
    identifier,
    cassandra.timestamp(periods[period]),
    name.."_"..period
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

-- Unsuported
function ResponseRateLimitingMetrics:find_by_primary_key()
  error("ratelimiting_metrics:find_by_primary_key() not yet implemented", 2)
end

function ResponseRateLimitingMetrics:delete(api_id, identifier, periods)
  error("ratelimiting_metrics:delete() not yet implemented", 2)
end

function ResponseRateLimitingMetrics:insert()
  error("ratelimiting_metrics:insert() not supported", 2)
end

function ResponseRateLimitingMetrics:update()
  error("ratelimiting_metrics:update() not supported", 2)
end

function ResponseRateLimitingMetrics:find()
  error("ratelimiting_metrics:find() not supported", 2)
end

function ResponseRateLimitingMetrics:find_by_keys()
  error("ratelimiting_metrics:find_by_keys() not supported", 2)
end

return { response_ratelimiting_metrics = ResponseRateLimitingMetrics }
