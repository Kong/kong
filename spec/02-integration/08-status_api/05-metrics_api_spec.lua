-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"


for _, strategy in helpers.all_strategies() do
  describe("Metrics API - with strategy #" .. strategy, function()
    describe("`/metrics` endpoint", function()
      local client
      local db_port = strategy == "postgres" and 5432 or 9042
      local db_proxy = helpers.db_proxy.new({ db_port = db_port })

      setup(function()
        assert(db_proxy:start())

        assert(helpers.start_kong({
          database = strategy,
          pg_port = db_proxy.db_proxy_port,
          status_listen = "127.0.0.1:9500",
          db_cache_warmup_entities = "workspaces",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        client = helpers.http_client("127.0.0.1", 9500, 60000)
      end)

      lazy_teardown(function()
        if client then client:close() end
        assert(helpers.stop_kong())
        assert(db_proxy:stop())
      end)

      it(" can work even if database is down", function()
        local res = assert(client:send {
          method = "GET",
          path = "/metrics"
        })
        assert.res_status(200, res)
        assert.res_status(200, db_proxy:status(false))

        res = assert(client:send {
          method = "GET",
          path = "/metrics"
        })
        assert.res_status(200, res)
      end)
    end)
  end)
end
