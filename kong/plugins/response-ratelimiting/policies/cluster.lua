local timestamp = require "kong.tools.timestamp"
local cassandra = require "cassandra"


local kong = kong
local concat = table.concat
local pairs = pairs
local floor = math.floor
local fmt = string.format


return {
  cassandra = {
    increment = function(connector, identifier, name, current_timestamp, service_id, route_id, value)
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        local res, err = connector:query([[
          UPDATE response_ratelimiting_metrics
             SET value = value + ?
           WHERE identifier = ?
             AND period = ?
             AND period_date = ?
             AND service_id = ?
             AND route_id = ?
        ]], {
          cassandra.counter(value),
          identifier,
          name .. "_" .. period,
          cassandra.timestamp(period_date),
          cassandra.uuid(service_id),
          cassandra.uuid(route_id),
        })
        if not res then
          kong.log.err("cluster policy: could not increment ",
                       "cassandra counter for period '", period, "': ", err)
        end
      end

      return true
    end,
    find = function(connector, identifier, name, period, current_timestamp, service_id, route_id)
      local periods = timestamp.get_timestamps(current_timestamp)

      local rows, err = connector:query([[
        SELECT value
          FROM response_ratelimiting_metrics
         WHERE identifier = ?
           AND period = ?
           AND period_date = ?
           AND service_id = ?
           AND route_id = ?
      ]], {
        identifier,
        name .. "_" .. period,
        cassandra.timestamp(periods[period]),
        cassandra.uuid(service_id),
        cassandra.uuid(route_id),
      })

      if not rows then
        return nil, err
      end

      if #rows <= 1 then
        return rows[1]
      end

      return nil, "bad rows result"
    end,
  },
  postgres = {
    increment = function(connector, identifier, name, current_timestamp, service_id, route_id, value)
      local buf = { "BEGIN" }
      local len = 1
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        len = len + 1
        buf[len] = fmt([[
          INSERT INTO "response_ratelimiting_metrics" ("identifier", "period", "period_date", "service_id", "route_id", "value")
               VALUES ('%s', '%s_%s', TO_TIMESTAMP('%s') AT TIME ZONE 'UTC', '%s', '%s', %d)
          ON CONFLICT ("identifier", "period", "period_date", "service_id", "route_id") DO UPDATE
                  SET "value" = "response_ratelimiting_metrics"."value" + EXCLUDED."value";
        ]], identifier, name, period, floor(period_date / 1000), service_id, route_id, value)
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
    find = function(connector, identifier, name, period, current_timestamp, service_id, route_id)
      local periods = timestamp.get_timestamps(current_timestamp)

      local q = fmt([[
        SELECT "value"
          FROM "response_ratelimiting_metrics"
         WHERE "identifier" = '%s'
           AND "period" = '%s_%s'
           AND "period_date" = TO_TIMESTAMP('%s') AT TIME ZONE 'UTC'
           AND "service_id" = '%s'
           AND "route_id" = '%s'
      ]], identifier, name, period, floor(periods[period] / 1000), service_id, route_id)

      local res, err = connector:query(q)
      if not res then
        return nil, err
      end

      return res[1]
    end,
  }
}
