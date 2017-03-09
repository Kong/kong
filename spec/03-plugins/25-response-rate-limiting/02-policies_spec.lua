local uuid = require("kong.tools.utils").uuid
local helpers = require "spec.helpers"
local policies = require "kong.plugins.rate-limiting.policies"
local timestamp = require "kong.tools.timestamp"

describe("Plugin: response-ratelimiting (policies)", function()
  describe("cluster", function()
    local cluster_policy = policies.cluster

    local api_id = uuid()
    local identifier = uuid()

    setup(function()
      local singletons = require "kong.singletons"
      singletons.dao = helpers.dao

      helpers.dao:truncate_tables()
    end)

    after_each(function()
      helpers.dao:truncate_tables()
    end)

    it("should return nil when ratelimiting metrics are not existing", function()
      local current_timestamp = 1424217600
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(nil, api_id, identifier,
                                                   current_timestamp, period, "video"))
        assert.equal(0, metric)
      end
    end)

    it("should increment ratelimiting metrics with the given period", function()
      local current_timestamp = 1424217600
      local periods = timestamp.get_timestamps(current_timestamp)

      -- First increment
      assert(cluster_policy.increment(nil, api_id, identifier, current_timestamp, 1, "video"))

      -- First select
      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(nil, api_id, identifier,
                                                   current_timestamp, period, "video"))
        assert.equal(1, metric)
      end

      -- Second increment
      assert(cluster_policy.increment(nil, api_id, identifier, current_timestamp, 1, "video"))

      -- Second select
      for period, period_date in pairs(periods) do
        local metric = assert(cluster_policy.usage(nil, api_id, identifier,
                                                   current_timestamp, period, "video"))
        assert.equal(2, metric)
      end

      -- 1 second delay
      current_timestamp = 1424217601
      periods = timestamp.get_timestamps(current_timestamp)

      -- Third increment
      assert(cluster_policy.increment(nil, api_id, identifier, current_timestamp, 1, "video"))

      -- Third select with 1 second delay
      for period, period_date in pairs(periods) do

        local expected_value = 3

        if period == "second" then
          expected_value = 1
        end

        local metric = assert(cluster_policy.usage(nil, api_id, identifier,
                                                   current_timestamp, period, "video"))
        assert.equal(expected_value, metric)
      end
    end)
  end)
end)
