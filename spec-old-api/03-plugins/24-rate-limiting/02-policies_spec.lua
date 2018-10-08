local uuid = require("kong.tools.utils").uuid
local helpers = require "spec.helpers"
local policies = require "kong.plugins.rate-limiting.policies"
local timestamp = require "kong.tools.timestamp"

describe("Plugin: rate-limiting (policies)", function()
  describe("cluster", function()
    local cluster_policy = policies.cluster

    local api_id = uuid()
    local conf = { api_id = api_id }
    local identifier = uuid()
    local dao

    setup(function()
      local _, db
      _, db, dao = helpers.get_db_utils()
      _G.kong = _G.kong or { db = db }

      dao:truncate_tables()
    end)
    after_each(function()
      dao:truncate_tables()
    end)

    it("returns 0 when rate-limiting metrics don't exist yet", function()
      local current_timestamp = 1424217600
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(conf, identifier,
                                                   current_timestamp, period))
        assert.equal(0, metric)
      end
    end)

    it("increments rate-limiting metrics with the given period", function()
      local current_timestamp = 1424217600
      local periods = timestamp.get_timestamps(current_timestamp)

      local limits = {
        second = 100,
        minute = 100,
        hour = 100,
        day = 100,
        month = 100,
        year = 100
      }

      -- First increment
      assert(cluster_policy.increment(conf, limits, identifier, current_timestamp, 1))

      -- First select
      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(conf, identifier,
                                                   current_timestamp, period))
        assert.equal(1, metric)
      end

      -- Second increment
      assert(cluster_policy.increment(conf, limits, identifier, current_timestamp, 1))

      -- Second select
      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(conf, identifier,
                                                   current_timestamp, period))
        assert.equal(2, metric)
      end

      -- 1 second delay
      current_timestamp = 1424217601
      periods = timestamp.get_timestamps(current_timestamp)

      -- Third increment
      assert(cluster_policy.increment(conf, limits, identifier, current_timestamp, 1))

      -- Third select with 1 second delay
      for period, period_date in pairs(periods) do
        local expected_value = 3
        if period == "second" then
          expected_value = 1
        end

        local metric = assert(cluster_policy.usage(conf, identifier,
                                                   current_timestamp, period))
        assert.equal(expected_value, metric)
      end
    end)
  end)
end)
