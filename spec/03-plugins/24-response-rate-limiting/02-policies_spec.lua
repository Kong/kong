-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uuid      = require("kong.tools.utils").uuid
local helpers   = require "spec.helpers"
local timestamp = require "kong.tools.timestamp"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-ratelimiting (policies) [#" .. strategy .. "]", function()
    describe("cluster", function()
      local identifier = uuid()
      local conf       = { route = { id = uuid() }, service = { id = uuid() } }

      local db
      local policies

      lazy_setup(function()
        local _
        _, db = helpers.get_db_utils(strategy)

        if _G.kong then
          _G.kong.db = db
        else
          _G.kong = { db = db }
        end

        package.loaded["kong.plugins.response-ratelimiting.policies"] = nil
        policies = require "kong.plugins.response-ratelimiting.policies"
      end)

      before_each(function()
        db:truncate("response_ratelimiting_metrics")
      end)

      it("should return 0 when ratelimiting metrics are not existing", function()
        local current_timestamp = 1424217600
        local periods = timestamp.get_timestamps(current_timestamp)

        for period in pairs(periods) do
          local metric = assert(policies.cluster.usage(conf, identifier, "video",
                                                       period, current_timestamp))
          assert.equal(0, metric)
        end
      end)

      it("should increment ratelimiting metrics with the given period", function()
        local current_timestamp = 1424217600
        local periods = timestamp.get_timestamps(current_timestamp)

        -- First increment
        assert(policies.cluster.increment(conf, identifier, "video", current_timestamp, 1))

        -- First select
        for period in pairs(periods) do
          local metric = assert(policies.cluster.usage(conf, identifier, "video",
                                                       period, current_timestamp))
          assert.equal(1, metric)
        end

        -- Second increment
        assert(policies.cluster.increment(conf, identifier, "video", current_timestamp, 1))

        -- Second select
        for period in pairs(periods) do
          local metric = assert(policies.cluster.usage(conf, identifier, "video",
                                                       period, current_timestamp))
          assert.equal(2, metric)
        end

        -- 1 second delay
        current_timestamp = 1424217601
        periods = timestamp.get_timestamps(current_timestamp)

        -- Third increment
        assert(policies.cluster.increment(conf, identifier, "video", current_timestamp, 1))

        -- Third select with 1 second delay
        for period in pairs(periods) do

          local expected_value = 3

          if period == "second" then
            expected_value = 1
          end

          local metric = assert(policies.cluster.usage(conf, identifier, "video",
                                                       period, current_timestamp))
          assert.equal(expected_value, metric)
        end
      end)
    end)
  end)
end
