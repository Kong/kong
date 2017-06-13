local timestamp = require "kong.tools.timestamp"

local concat = table.concat
local pairs = pairs
local fmt = string.format
local log = ngx.log
local ERR = ngx.ERR

return {
  ["cassandra"] = {
    increment = function(db, limits, api_id, identifier, current_timestamp, value)
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        if limits[period] then
          local res, err = db:query([[
            UPDATE ratelimiting_metrics
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
            period,
          })
          if not res then
            log(ERR, "[rate-limiting] cluster policy: could not increment ",
                     "cassandra counter for period '", period, "': ", err)
          end
        end
      end

      return true
    end,
    find = function(db, api_id, identifier, current_timestamp, period)
      local periods = timestamp.get_timestamps(current_timestamp)

      local rows, err = db:query([[
        SELECT *
        FROM ratelimiting_metrics
        WHERE api_id = ? AND
              identifier = ? AND
              period_date = ? AND
              period = ?
      ]], {
        db.cassandra.uuid(api_id),
        identifier,
        db.cassandra.timestamp(periods[period]),
        period,
      })
      if not rows then       return nil, err
      elseif #rows <= 1 then return rows[1]
      else                   return nil, "bad rows result" end
    end,
  },
  ["postgres"] = {
    increment = function(db, limits, api_id, identifier, current_timestamp, value)
      local buf = {}
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        if limits[period] then
          buf[#buf+1] = fmt([[
            SELECT increment_rate_limits('%s', '%s', '%s', to_timestamp('%s')
            at time zone 'UTC', %d)
          ]], api_id, identifier, period, period_date/1000, value)
        end
      end

      local res, err = db:query(concat(buf, ";"))
      if not res then
        return nil, err
      end

      return true
    end,
    find = function(db, api_id, identifier, current_timestamp, period)
      local periods = timestamp.get_timestamps(current_timestamp)

      local q = fmt([[
        SELECT *, extract(epoch from period_date)*1000 AS period_date
        FROM ratelimiting_metrics
        WHERE api_id = '%s' AND
              identifier = '%s' AND
              period_date = to_timestamp('%s') at time zone 'UTC' AND
              period = '%s'
      ]], api_id, identifier, periods[period]/1000, period)

      local res, err = db:query(q)
      if not res or err then
        return nil, err
      end

      return res[1]
    end,
  }
}
