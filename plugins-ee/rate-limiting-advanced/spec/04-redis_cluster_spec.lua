-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local REDIS_CLUSTER_ADDRESSES = ee_helpers.redis_cluster_addresses
local REDIS_CLUSTER_NODE_ADDRESS = REDIS_CLUSTER_ADDRESSES[1]
local REDIS_CLUSTER_NODE_HOST, REDIS_CLUSTER_NODE_PORT =
      REDIS_CLUSTER_NODE_ADDRESS:match("([^:]+):([^:]+)")
REDIS_CLUSTER_NODE_PORT = tonumber(REDIS_CLUSTER_NODE_PORT)

for _, strategy in helpers.all_strategies() do
  describe("rate-limiting-advanced redis cluster #" .. strategy, function()
    local bp
    local route
    lazy_setup(function()
      bp = helpers.get_db_utils(nil, nil, {"rate-limiting-advanced"})

      route = assert(bp.routes:insert {
        name  = "test",
        hosts = { "test1.test" },
      })

      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route.id },
        config = {
          strategy = "redis",
          window_size = { 1 },
          limit = { 10 },
          sync_rate = 0.1,
          -- deliberately simulate a user configuring a redis cluster node to host/port
          redis = {
            host = REDIS_CLUSTER_NODE_HOST,
            port = REDIS_CLUSTER_NODE_PORT,
          },
        }
      })

      assert(helpers.start_kong({
        plugins = "rate-limiting-advanced",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("errors of the queries in pipeline show in error log", function()

      local proxy_client = helpers.proxy_client()
      assert
      .with_timeout(5)
      .eventually(function()
        local res = proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "test1.test",
          }
        }
        assert(res.status == 200 or res.status == 429)

        assert.logfile().has.line("in the get counters pipeline failed: MOVED", true, 0.1)
        assert.logfile().has.line("in the push diffs pipeline failed: MOVED", true, 0.1)
      end)

      proxy_client:close()
    end)
  end)
end
