local uuid = require("kong.tools.utils").uuid
local helpers = require "spec.helpers"
local policies = require "kong.plugins.response-ratelimiting.policies"
local timestamp = require "kong.tools.timestamp"

describe("Plugin: response-ratelimiting (policies)", function()
  describe("cluster", function()
    local cluster_policy = policies.cluster

    local api_id = uuid()
    local conf = { api_id = api_id }
    local identifier = uuid()
    local dao

    setup(function()
      dao = select(3, helpers.get_db_utils())

      local singletons = require "kong.singletons"
      singletons.dao = dao

      dao:truncate_tables()
    end)

    after_each(function()
      dao:truncate_tables()
    end)

    it("should return nil when ratelimiting metrics are not existing", function()
      local current_timestamp = 1424217600
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(conf, identifier,
                                                   current_timestamp, period, "video"))
        assert.equal(0, metric)
      end
    end)

    it("should increment ratelimiting metrics with the given period", function()
      local current_timestamp = 1424217600
      local periods = timestamp.get_timestamps(current_timestamp)

      -- First increment
      assert(cluster_policy.increment(conf, identifier, current_timestamp, 1, "video"))

      -- First select
      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(conf, identifier,
                                                   current_timestamp, period, "video"))
        assert.equal(1, metric)
      end

      -- Second increment
      assert(cluster_policy.increment(conf, identifier, current_timestamp, 1, "video"))

      -- Second select
      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(conf, identifier,
                                                   current_timestamp, period, "video"))
        assert.equal(2, metric)
      end

      -- 1 second delay
      current_timestamp = 1424217601
      periods = timestamp.get_timestamps(current_timestamp)

      -- Third increment
      assert(cluster_policy.increment(conf, identifier, current_timestamp, 1, "video"))

      -- Third select with 1 second delay
      for period, period_date in pairs(periods) do

        local expected_value = 3

        if period == "second" then
          expected_value = 1
        end

        local metric = assert(cluster_policy.usage(conf, identifier,
                                                   current_timestamp, period, "video"))
        assert.equal(expected_value, metric)
      end
    end)
  end)
end)
