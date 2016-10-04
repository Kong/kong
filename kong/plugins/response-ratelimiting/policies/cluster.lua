local timestamp = require "kong.tools.timestamp"

local concat = table.concat
local pairs = pairs
local fmt = string.format
local log = ngx.log
local ERR = ngx.ERR

return {
  ["cassandra"] = {
    increment = function(db, api_id, identifier, current_timestamp, value, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        local res, err = db:query([[
          UPDATE response_ratelimiting_metrics
          SET value = value + ?
          WHERE api_id = ? AND
                identifier = ? AND
                period_date = ? AND
                period = ?
        ]], {
          db.cassandra.counter(value),
          db.cassandra.uuid(api_id),
          identifier,
          db.cassandra.timestamp(period_date),
          name.."_"..period,
        })
        if not res then
          log(ERR, "[response-ratelimiting] cluster policy: could not increment ",
                   "cassandra counter for period '", period, "': ", err)
        end
      end

      return true
    end,
    find = function(db, api_id, identifier, current_timestamp, period, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      local rows, err = db:query([[
        SELECT * FROM response_ratelimiting_metrics
        WHERE api_id = ? AND
              identifier = ? AND
              period_date = ? AND
              period = ?
      ]], {
        db.cassandra.uuid(api_id),
        identifier,
        db.cassandra.timestamp(periods[period]),
        name.."_"..period,
      })
      if not rows then       return nil, err
      elseif #rows <= 1 then return rows[1]
      else                   return nil, "bad rows result" end
    end,
  },
  ["postgres"] = {
    increment = function(db, api_id, identifier, current_timestamp, value, name)
      local buf = {}
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        buf[#buf+1] = fmt([[
          SELECT increment_response_rate_limits('%s', '%s', '%s_%s', to_timestamp('%s')
          at time zone 'UTC', %d)
        ]], api_id, identifier, name, period, period_date/1000, value)
      end

      local res, err = db:query(concat(buf, ";"))
      if not res then return nil, err end

      return true
    end,
    find = function(db, api_id, identifier, current_timestamp, period, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      local q = fmt([[
        SELECT *, extract(epoch from period_date)*1000 AS period_date
        FROM response_ratelimiting_metrics
        WHERE api_id = '%s' AND
              identifier = '%s' AND
              period_date = to_timestamp('%s') at time zone 'UTC' AND
              period = '%s_%s'
      ]], api_id, identifier, periods[period]/1000, name, period)

      local res, err = db:query(q)
      if not res or err then return nil, err end

      return res[1]
    end,
  }
}
