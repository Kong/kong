local timestamp = require "kong.tools.timestamp"
local cassandra = require "cassandra"


local kong = kong
local concat = table.concat
local pairs = pairs
local floor = math.floor
local fmt = string.format


local EXPIRATION = require "kong.plugins.rate-limiting.expiration"


local find
do
  local find_pk = {}

  find = function(identifier, period, current_timestamp, service_id, route_id)
      local periods = timestamp.get_timestamps(current_timestamp)

      find_pk.identifier  = identifier
      find_pk.period      = period
      find_pk.period_date = floor(periods[period] / 1000)
      find_pk.service_id  = service_id
      find_pk.route_id    = route_id

      return kong.db.ratelimiting_metrics:select(find_pk)
  end
end


return {
  cassandra = {
    increment = function(connector, limits, identifier, current_timestamp, service_id, route_id, value)
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        if limits[period] then
          local res, err = connector:query([[
            UPDATE ratelimiting_metrics
               SET value = value + ?
             WHERE identifier = ?
               AND period = ?
               AND period_date = ?
               AND service_id = ?
               AND route_id = ?
          ]], {
            cassandra.counter(value),
            identifier,
            period,
            cassandra.timestamp(period_date),
            cassandra.uuid(service_id),
            cassandra.uuid(route_id),
          })
          if not res then
            kong.log.err("cluster policy: could not increment cassandra counter for period '",
                         period, "': ", err)
          end
        end
      end

      return true
    end,
    find = find,
  },
  postgres = {
    increment = function(connector, limits, identifier, current_timestamp, service_id, route_id, value)
      local buf = { "BEGIN" }
      local len = 1
      local periods = timestamp.get_timestamps(current_timestamp)
      for period, period_date in pairs(periods) do
        if limits[period] then
          len = len + 1
          buf[len] = fmt([[
            INSERT INTO "ratelimiting_metrics" ("identifier", "period", "period_date", "service_id", "route_id", "value", "ttl")
                 VALUES ('%s', '%s', TO_TIMESTAMP('%s') AT TIME ZONE 'UTC', '%s', '%s', %d, CURRENT_TIMESTAMP AT TIME ZONE 'UTC' + INTERVAL '%d second')
            ON CONFLICT ("identifier", "period", "period_date", "service_id", "route_id") DO UPDATE
                    SET "value" = "ratelimiting_metrics"."value" + EXCLUDED."value"
          ]], identifier, period, floor(period_date / 1000), service_id, route_id, value, EXPIRATION[period])
        end
      end

      if len > 1 then
        local sql
        if len == 2 then
          sql = buf[2]

        else
          buf[len + 1] = "COMMIT;"
          sql = concat(buf, ";\n")
        end

        local res, err = connector:query(sql)
        if not res then
          return nil, err
        end
      end

      return true
    end,
    find = find,
  },
}
