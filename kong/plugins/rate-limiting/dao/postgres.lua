local PostgresDB = require "kong.dao.postgres_db"
local timestamp = require "kong.tools.timestamp"
local fmt = string.format
local concat = table.concat

local _M = PostgresDB:extend()

_M.table = "ratelimiting_metrics"
_M.schema = require("kong.plugins.response-ratelimiting.schema")

function _M:increment(api_id, identifier, current_timestamp, value)
  local buf = {}
  local periods = timestamp.get_timestamps(current_timestamp)
  for period, period_date in pairs(periods) do
    buf[#buf + 1] = fmt("SELECT increment_rate_limits('%s', '%s', '%s', to_timestamp('%s') at time zone 'UTC', %d)",
                        api_id, identifier, period, period_date/1000, value)
  end

  local queries = concat(buf, ";")

  local res, err = self:query(queries)
  if not res then
    return false, err
  end
  return true
end

function _M:find(api_id, identifier, current_timestamp, period)
  local periods = timestamp.get_timestamps(current_timestamp)

  local q = fmt([[SELECT *, extract(epoch from period_date)*1000 AS period_date FROM ratelimiting_metrics WHERE
                  api_id = '%s' AND
                  identifier = '%s' AND
                  period_date = to_timestamp('%s') at time zone 'UTC' AND
                  period = '%s'
  ]], api_id, identifier, periods[period]/1000, period)

  local res, err = self:query(q)
  if not res or err then
    return nil, err
  end

  return res[1]
end

function _M:count()
  return _M.super.count(self, _M.table, nil, _M.schema)
end

return {ratelimiting_metrics = _M}
