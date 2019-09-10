local uuid      = require("kong.tools.utils").uuid
local helpers   = require "spec.helpers"
local timestamp = require "kong.tools.timestamp"

local get_local_key = function(conf, identifier, period, period_date)
  return string.format("ratelimit:%s:%s:%s:%s:%s",
    conf.route_id, conf.service_id, identifier, period_date, period)
end

describe("Plugin: rate-limiting (policies)", function()

  local policies

  lazy_setup(function()
    package.loaded["kong.plugins.rate-limiting.policies"] = nil
    policies = require "kong.plugins.rate-limiting.policies"
  end)

  describe("local", function()
    local identifier = uuid()
    local conf       = { route_id = uuid(), service_id = uuid() }

    local shm = ngx.shared.kong_rate_limiting_counters

    before_each(function()
      shm:flush_all()
      shm:flush_expired()
    end)

    it("sets the TTL equal to one period when incrementing", function()
      local current_timestamp = 1553263548
      local periods = timestamp.get_timestamps(current_timestamp)

      local limits = {
        minute = 100,
        hour   = 100
      }

      assert(policies["local"].increment(conf, limits, identifier, current_timestamp, 1))

      local minute_key_ttl = shm:ttl(get_local_key(conf, identifier, "minute", periods.minute))
      local hour_key_ttl = shm:ttl(get_local_key(conf, identifier, "hour", periods.hour))

      assert(minute_key_ttl > 55 and minute_key_ttl <= 60)
      assert(hour_key_ttl > 3555 and hour_key_ttl <= 3600)
    end)

    it("expires after due time", function ()
      local timestamp = 569000048000

      assert(policies['local'].increment(conf, {second=100}, identifier, timestamp+20, 1))
      local v = shm:ttl(get_local_key(conf, identifier, 'second', timestamp))
      assert(v and v > 0, "wrong value")
      ngx.sleep(1.020)

      v = shm:ttl(get_local_key(conf, identifier, 'second', timestamp))
      assert(v == nil, "still there")
    end)
  end)

  for _, strategy in helpers.each_strategy() do
    describe("cluster [#" .. strategy .. "]", function()
      local identifier = uuid()
      local conf       = { route = { id = uuid() }, service = { id = uuid() } }

      local db

      lazy_setup(function()
        local _
        _, db = helpers.get_db_utils(strategy, {})

        if _G.kong then
          _G.kong.db = db
        else
          _G.kong = { db = db }
        end
      end)

      before_each(function()
        assert(db:truncate("ratelimiting_metrics"))
      end)

      it("returns 0 when rate-limiting metrics don't exist yet", function()
        local current_timestamp = 1424217600
        local periods = timestamp.get_timestamps(current_timestamp)

        for period in pairs(periods) do
          local metric = assert(policies.cluster.usage(conf, identifier, period, current_timestamp))
          assert.equal(0, metric)
        end
      end)

      it("increments rate-limiting metrics with the given period", function()
        local current_timestamp = 1424217600
        local periods = timestamp.get_timestamps(current_timestamp)

        local limits = {
          second = 100,
          minute = 100,
          hour   = 100,
          day    = 100,
          month  = 100,
          year   = 100
        }

        -- First increment
        assert(policies.cluster.increment(conf, limits, identifier, current_timestamp, 1))

        -- First select
        for period in pairs(periods) do
          local metric = assert(policies.cluster.usage(conf, identifier, period, current_timestamp))
          assert.equal(1, metric)
        end

        -- Second increment
        assert(policies.cluster.increment(conf, limits, identifier, current_timestamp, 1))

        -- Second select
        for period in pairs(periods) do
          local metric = assert(policies.cluster.usage(conf, identifier, period, current_timestamp))
          assert.equal(2, metric)
        end

        -- 1 second delay
        current_timestamp = 1424217601
        periods = timestamp.get_timestamps(current_timestamp)

        -- Third increment
        assert(policies.cluster.increment(conf, limits, identifier, current_timestamp, 1))

        -- Third select with 1 second delay
        for period in pairs(periods) do
          local expected_value = 3
          if period == "second" then
            expected_value = 1
          end

          local metric = assert(policies.cluster.usage(conf, identifier, period, current_timestamp))
          assert.equal(expected_value, metric)
        end
      end)
    end)
  end

end)
