local uuid      = require("kong.tools.utils").uuid
local helpers   = require "spec.helpers"
local timestamp = require "kong.tools.timestamp"

local SYNC_RATE_REALTIME = -1

--[[
  basically a copy of `get_local_key()`
  in `kong/plugins/rate-limiting/policies/init.lua`
--]]
local EMPTY_UUID = "00000000-0000-0000-0000-000000000000"
local null = ngx.null
local function get_service_and_route_ids(conf)
  conf             = conf or {}

  local service_id = conf.service_id
  local route_id   = conf.route_id

  if not service_id or service_id == null then
    service_id = EMPTY_UUID
  end

  if not route_id or route_id == null then
    route_id = EMPTY_UUID
  end

  return service_id, route_id
end

local function get_local_key(conf, identifier, period, period_date)
  local service_id, route_id = get_service_and_route_ids(conf)

  return string.format("ratelimit:%s:%s:%s:%s:%s", route_id, service_id, identifier,
    period_date, period)
end

describe("Plugin: rate-limiting (policies)", function()

  local policies

  lazy_setup(function()
    package.loaded["kong.plugins.rate-limiting.policies"] = nil
    policies = require "kong.plugins.rate-limiting.policies"

    if not _G.kong then
      _G.kong.db = {}
    end

    _G.kong.timer = require("resty.timerng").new()
    _G.kong.timer:start()
  end)

  describe("local", function()
    local identifier = uuid()
    local conf       = { route_id = uuid(), service_id = uuid(), sync_rate = SYNC_RATE_REALTIME }

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
      local current_timestamp = 1553263548
      local periods = timestamp.get_timestamps(current_timestamp)

      local limits = {
        second = 100,
      }
      local cache_key = get_local_key(conf, identifier, 'second', periods.second)

      assert(policies['local'].increment(conf, limits, identifier, current_timestamp, 1))
      local v = assert(shm:ttl(cache_key))
      assert(v > 0, "wrong value")
      ngx.sleep(1.020)

      shm:flush_expired()
      local err
      v, err = shm:ttl(cache_key)
      assert(v == nil, "still there")
      assert.matches("not found", err)
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

  for _, sync_rate in ipairs{0.5, SYNC_RATE_REALTIME} do
    local current_timestamp = 1424217600
    local periods = timestamp.get_timestamps(current_timestamp)

    for period in pairs(periods) do
      describe("redis with sync rate: " .. sync_rate .. " period: " .. period, function()
        local identifier = uuid()
        local conf       = {
          route_id = uuid(),
          service_id = uuid(),
          redis = {
            host = helpers.redis_host,
            port = helpers.redis_port,
            database = 0,
          },
          sync_rate = sync_rate,
        }

        before_each(function()
          local red = require "resty.redis"
          local redis = assert(red:new())
          redis:set_timeout(1000)
          assert(redis:connect(conf.redis.host, conf.redis.port))
          redis:flushall()
          redis:close()
        end)

        it("increase & usage", function()
          --[[
            Just a simple test:
            - increase 1
            - check usage == 1
            - increase 1
            - check usage == 2
            - increase 1 (beyond the limit)
            - check usage == 3
          --]]

          local metric = assert(policies.redis.usage(conf, identifier, period, current_timestamp))
          assert.equal(0, metric)

          for i = 1, 3 do
            -- "second" keys expire too soon to check the async increment.
            -- Let's verify all the other scenarios:
            if not (period == "second" and sync_rate ~= SYNC_RATE_REALTIME) then
              assert(policies.redis.increment(conf, { [period] = 2 }, identifier, current_timestamp, 1))

              -- give time to the async increment to happen
              if sync_rate ~= SYNC_RATE_REALTIME then
                local sleep_time = 1 + (sync_rate > 0 and sync_rate or 0)
                ngx.sleep(sleep_time)
              end

              metric = assert(policies.redis.usage(conf, identifier, period, current_timestamp))
              assert.equal(i, metric)
            end
          end
        end)
      end)
    end
  end
end)
