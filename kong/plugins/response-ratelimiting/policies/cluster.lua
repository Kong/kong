local timestamp = require "kong.tools.timestamp"
local cassandra = require "cassandra"

local concat = table.concat
local pairs = pairs
local fmt = string.format


local NULL_UUID = "00000000-0000-0000-0000-000000000000"


return {
  ["cassandra"] = {
    increment = function(connector, route_id, service_id, identifier, current_timestamp, value, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        local res, err = connector:query([[
          UPDATE response_ratelimiting_metrics
          SET value = value + ?
          WHERE route_id = ?
            AND service_id = ?
            AND api_id = ?
            AND identifier = ?
            AND period_date = ?
            AND period = ?
        ]], {
          cassandra.counter(value),
          cassandra.uuid(route_id),
          cassandra.uuid(service_id),
          cassandra.uuid(NULL_UUID),
          identifier,
          cassandra.timestamp(period_date),
          name .. "_" .. period
        })

        if not res then
          kong.log.err("cluster policy: could not increment ",
                       "cassandra counter for period '", period, "': ", err)
        end
      end

      return true
    end,
    increment_api = function(connector, api_id, identifier, current_timestamp, value, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        local res, err = connector:query([[
          UPDATE response_ratelimiting_metrics
          SET value = value + ?
          WHERE api_id = ? AND
                route_id = ? AND
                service_id = ? AND
                identifier = ? AND
                period_date = ? AND
                period = ?
        ]], {
          cassandra.counter(value),
          cassandra.uuid(api_id),
          cassandra.uuid(NULL_UUID),
          cassandra.uuid(NULL_UUID),
          identifier,
          cassandra.timestamp(period_date),
          name .. "_" .. period,
        })
        if not res then
          kong.log.err("cluster policy: could not increment ",
                       "cassandra counter for period '", period, "': ", err)
        end
      end

      return true
    end,
    find = function(connector, route_id, service_id, identifier, current_timestamp, period, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      local rows, err = connector:query([[
        SELECT * FROM response_ratelimiting_metrics
        WHERE route_id = ?
          AND service_id = ?
          AND api_id = ?
          AND identifier = ?
          AND period_date = ?
          AND period = ?
      ]], {
        cassandra.uuid(route_id),
        cassandra.uuid(service_id),
        cassandra.uuid(NULL_UUID),
        identifier,
        cassandra.timestamp(periods[period]),
        name .. "_" .. period,
      })

      if not rows then       return nil, err
      elseif #rows <= 1 then return rows[1]
      else                   return nil, "bad rows result" end
    end,
    find_api = function(connector, api_id, identifier, current_timestamp, period, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      local rows, err = connector:query([[
        SELECT * FROM response_ratelimiting_metrics
        WHERE api_id = ? AND
              route_id = ? AND
              service_id = ? AND
              identifier = ? AND
              period_date = ? AND
              period = ?
      ]], {
        cassandra.uuid(api_id),
        cassandra.uuid(NULL_UUID),
        cassandra.uuid(NULL_UUID),
        identifier,
        cassandra.timestamp(periods[period]),
        name .. "_" .. period,
      })
      if not rows then       return nil, err
      elseif #rows <= 1 then return rows[1]
      else                   return nil, "bad rows result" end
    end,
  },
  ["postgres"] = {
    increment = function(connector, route_id, service_id, identifier, current_timestamp, value, name)
      local buf = {}
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        buf[#buf + 1] = fmt([[
          INSERT INTO response_ratelimiting_metrics AS old(identifier, period, period_date, service_id, route_id, value)
                      VALUES ('%s', '%s_%s', to_timestamp('%s') at time zone 'UTC', '%s', '%s', %d)
          ON CONFLICT ON CONSTRAINT response_ratelimiting_metrics_pkey
          DO UPDATE SET value = old.value + %d;
        ]], identifier, name, period, period_date/1000, service_id, route_id, value, value)
      end

      local res, err = connector:query(concat(buf, ";"))
      if not res then
        return nil, err
      end

      return true
    end,
    increment_api = function(connector, api_id, identifier, current_timestamp, value, name)
      local buf = {}
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        buf[#buf + 1] = fmt([[
          INSERT INTO response_ratelimiting_metrics AS old(identifier, period, period_date, api_id, value)
                      VALUES ('%s', '%s_%s', to_timestamp('%s') at time zone 'UTC', '%s', %d)
          ON CONFLICT ON CONSTRAINT response_ratelimiting_metrics_pkey
          DO UPDATE SET value = old.value + %d;
        ]], identifier, name, period, period_date/1000, api_id, value, value)
      end

      local res, err = connector:query(concat(buf, ";"))
      if not res then
        return nil, err
      end

      return true
    end,
    find = function(connector, route_id, service_id, identifier, current_timestamp, period, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      local q = fmt([[
        SELECT *, extract(epoch from period_date)*1000 AS period_date
        FROM response_ratelimiting_metrics
        WHERE route_id = '%s'
          AND service_id = '%s'
          AND identifier = '%s'
          AND period_date = to_timestamp('%s') at time zone 'UTC'
          AND period = '%s_%s'
      ]], route_id, service_id, identifier, periods[period]/1000, name, period)

      local res, err = connector:query(q)
      if not res then
        return nil, err
      end

      return res[1]
    end,
    find_api = function(connector, api_id, identifier, current_timestamp, period, name)
      local periods = timestamp.get_timestamps(current_timestamp)

      local q = fmt([[
        SELECT *, extract(epoch from period_date)*1000 AS period_date
        FROM response_ratelimiting_metrics
        WHERE api_id = '%s' AND
              identifier = '%s' AND
              period_date = to_timestamp('%s') at time zone 'UTC' AND
              period = '%s_%s'
      ]], api_id, identifier, periods[period]/1000, name, period)

      local res, err = connector:query(q)
      if not res then
        return nil, err
      end

      return res[1]
    end,
  }
}
