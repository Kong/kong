local BaseDao = require "kong.dao.cassandra.base_dao"
local cassandra = require "cassandra"
local timestamp = require "kong.tools.timestamp"

local ngx_log = ngx and ngx.log or print
local ngx_err = ngx and ngx.ERR
local tostring = tostring

local RateLimitingMetrics = BaseDao:extend()

function RateLimitingMetrics:new(properties)
  self._table = "ratelimiting_metrics"
  self.queries = {
    increment_counter = [[ UPDATE ratelimiting_metrics SET value = value + ? WHERE api_id = ? AND
                            identifier = ? AND
                            period_date = ? AND
                            period = ?; ]],
    select_one = [[ SELECT * FROM ratelimiting_metrics WHERE api_id = ? AND
                      identifier = ? AND
                      period_date = ? AND
                      period = ?; ]],
    delete = [[ DELETE FROM ratelimiting_metrics WHERE api_id = ? AND
                  identifier = ? AND
                  period_date = ? AND
                  period = ?; ]]
  }

  RateLimitingMetrics.super.new(self, properties)
end

function RateLimitingMetrics:increment(api_id, identifier, current_timestamp, value)
  local periods = timestamp.get_timestamps(current_timestamp)
  local options = self._factory:get_session_options()
  local session, err = cassandra.spawn_session(options)
  if err then
    ngx_log(ngx_err, "[rate-limiting] could not spawn session to Cassandra: "..tostring(err))
    return
  end

  local ok = true
  for period, period_date in pairs(periods) do
    local res, err = session:execute(self.queries.increment_counter, {
      cassandra.counter(value),
      cassandra.uuid(api_id),
      identifier,
      cassandra.timestamp(period_date),
      period
    })
    if not res then
      ok = false
      ngx_log(ngx_err, "[rate-limiting] could not increment counter for period '"..period.."': ", tostring(err))
    end
  end

  session:set_keep_alive()

  return ok
end

function RateLimitingMetrics:find_one(api_id, identifier, current_timestamp, period)
  local periods = timestamp.get_timestamps(current_timestamp)

  local metric, err = RateLimitingMetrics.super.execute(self, self.queries.select_one, {
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

-- Unsuported
function RateLimitingMetrics:find_by_primary_key()
  error("ratelimiting_metrics:find_by_primary_key() not yet implemented", 2)
end

function RateLimitingMetrics:delete(api_id, identifier, periods)
  error("ratelimiting_metrics:delete() not yet implemented", 2)
end

function RateLimitingMetrics:insert()
  error("ratelimiting_metrics:insert() not supported", 2)
end

function RateLimitingMetrics:update()
  error("ratelimiting_metrics:update() not supported", 2)
end

function RateLimitingMetrics:find()
  error("ratelimiting_metrics:find() not supported", 2)
end

function RateLimitingMetrics:find_by_keys()
  error("ratelimiting_metrics:find_by_keys() not supported", 2)
end

return {ratelimiting_metrics = RateLimitingMetrics}
