-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.all_strategies() do
  describe("rate-limiting-advanced redis cluster", function()
    local bp
    local route
    lazy_setup(function()
      bp = helpers.get_db_utils(nil, nil, {"rate-limiting-advanced"})

      route = assert(bp.routes:insert {
        name  = "test",
        hosts = { "test1.com" },
      })

      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route.id },
        config = {
          strategy = "redis",
          window_size = { 1 },
          limit = { 10 },
          sync_rate = 0.1,
          -- actually it's a redis cluster
          redis = {
            host = "localhost",
            port = 6381,
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
      assert.logfile().has.line("in the get counters pipeline failed: MOVED", true, 5)

      local proxy_client = helpers.proxy_client()
      assert
      .with_timeout(5)
      .eventually(function()
        local res = proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "test1.com",
          }
        }
        assert(res.status == 200 or res.status == 429)
        assert.logfile().has.line("in the push diffs pipeline failed: MOVED", true, 0.1)
      end)

      proxy_client:close()
    end)
  end)
end
