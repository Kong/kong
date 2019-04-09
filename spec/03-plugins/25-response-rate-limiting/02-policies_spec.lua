local uuid      = require("kong.tools.utils").uuid
local helpers   = require "spec.helpers"
local policies  = require "kong.plugins.response-ratelimiting.policies"
local timestamp = require "kong.tools.timestamp"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-ratelimiting (policies) [#" .. strategy .. "]", function()
    describe("cluster", function()
      local cluster_policy = policies.cluster

      local conf = { route = { id = uuid() }, service = { id = uuid() } }
      local identifier = uuid()

      local dao

      lazy_setup(function()
        local _, db
        _, db, dao = helpers.get_db_utils(strategy, {})
        _G.kong = _G.kong or { db = db }
      end)

      before_each(function()
        dao.db:truncate_table("response_ratelimiting_metrics")
      end)

      it("should return nil when ratelimiting metrics are not existing", function()
        local current_timestamp = 1424217600
        local periods = timestamp.get_timestamps(current_timestamp)

        for period in pairs(periods) do
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
        for period in pairs(periods) do
          local metric = assert(cluster_policy.usage(conf, identifier,
                                                     current_timestamp, period, "video"))
          assert.equal(1, metric)
        end

        -- Second increment
        assert(cluster_policy.increment(conf, identifier, current_timestamp, 1, "video"))

        -- Second select
        for period in pairs(periods) do
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
        for period in pairs(periods) do

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
end
