local uuid      = require("kong.tools.utils").uuid
local helpers   = require "spec.helpers"
local timestamp = require "kong.tools.timestamp"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: rate-limiting (policies) [#" .. strategy .. "]", function()
    describe("cluster", function()
      local identifier = uuid()
      local conf       = { route = { id = uuid() }, service = { id = uuid() } }

      local db
      local dao
      local policies

      setup(function()
        local _
        _, db, dao = helpers.get_db_utils(strategy)

        if _G.kong then
          _G.kong.db = db
        else
          _G.kong = { db = db }
        end

        package.loaded["kong.plugins.rate-limiting.policies"] = nil
        policies = require "kong.plugins.rate-limiting.policies"
      end)

      after_each(function()
        assert(db:truncate())
        dao:truncate_tables()
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
  end)
end
