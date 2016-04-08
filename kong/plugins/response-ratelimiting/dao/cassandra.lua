local CassandraDB = require "kong.dao.cassandra_db"
local cassandra = require "cassandra"
local timestamp = require "kong.tools.timestamp"

local _M = CassandraDB:extend()

_M.table = "response_ratelimiting_metrics"
_M.schema = require("kong.plugins.response-ratelimiting.schema")

function _M:increment(api_id, identifier, current_timestamp, value, name)
  local periods = timestamp.get_timestamps(current_timestamp)
  local options = self:_get_conn_options()
  local session, err = cassandra.spawn_session(options)
  if err then
    ngx.log(ngx.ERR, "[response-ratelimiting] could not spawn session to Cassandra: "..tostring(err))
    return nil, err
  end

  local ok = true
  for period, period_date in pairs(periods) do
    local res, err = session:execute([[
      UPDATE response_ratelimiting_metrics SET value = value + ? WHERE
        api_id = ? AND
        identifier = ? AND
        period_date = ? AND
        period = ?
    ]], {
      cassandra.counter(value),
      cassandra.uuid(api_id),
      identifier,
      cassandra.timestamp(period_date),
      name.."_"..period
    })
    if not res then
      ok = false
      ngx.log(ngx.ERR, "[response-ratelimiting] could not increment counter for period '"..period.."': "..tostring(err))
    end
  end

  session:set_keep_alive()

  return ok
end

function _M:find(api_id, identifier, current_timestamp, period, name)
  local periods = timestamp.get_timestamps(current_timestamp)
  local rows, err = self:query([[
    SELECT * FROM response_ratelimiting_metrics WHERE
      api_id = ? AND
      identifier = ? AND
      period_date = ? AND
      period = ?
  ]], {
    cassandra.uuid(api_id),
    identifier,
    cassandra.timestamp(periods[period]),
    name.."_"..period
  })
  if err then
    return nil, err
  elseif #rows > 0 then
    return rows[1]
  end
end

function _M:count()
  return _M.super.count(self, _M.table, nil, _M.schema)
end

return {response_ratelimiting_metrics = _M}
