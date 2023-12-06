-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("Plugin upstream-timeout (#" .. strategy .. ")", function()
    local admin_client
    local proxy_client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, {
        "services",
        "routes",
        "plugins"
      }, { "upstream-timeout" })

      local delay_service_1 = assert(bp.services:insert({
        name = "no-delay-service",
        path = "/delay/1",                   -- 1 second delay
        read_timeout = 1                     -- 1 millisecond timeout
      }))
      local delay_service_2 = assert(bp.services:insert({
        name = "delay-service",
        path = "/delay/2",                    -- 2 second delay
        read_timeout = 5000                   -- 5 second timeout
      }))

      local delay_route_1 = assert(bp.routes:insert({
        hosts = { "delay1.test" },
        service = { id = delay_service_1.id }
      }))
      local delay_route_2 = assert(bp.routes:insert({
        hosts = { "delay2.test" },
        service = { id = delay_service_2.id }
      }))
      assert(bp.routes:insert({
        hosts = { "noPlugin.delay1.test" },
        service = { id = delay_service_1.id }
      }))
      assert(bp.routes:insert({
        hosts = { "noPlugin.delay2.test"},
        service = { id = delay_service_2.id }
      }))

      assert(bp.plugins:insert {
        route = { id = delay_route_1.id },
        name = "upstream-timeout",
        config = {
          read_timeout = 2000
        }
      })
      assert(bp.plugins:insert {
        route = { id = delay_route_2.id },
        name = "upstream-timeout",
        config = {
          read_timeout = 1000
        }
      })

      assert(helpers.start_kong({
        database = db_strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled, upstream-timeout"
      }))
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client and admin_client then
        proxy_client:close()
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    describe("request upstream", function()
      local function upstream_request(host)
        return proxy_client:send({
          method = "GET",
          path = "/",
          headers = {
            host = host
          }
        })
      end
      it("with service-configured timeout obeys service timeout", function()
        local res = assert(upstream_request("noPlugin.delay1.test"))
        assert.response(res).has.status(504)

        res = assert(upstream_request("noPlugin.delay2.test"))
        assert.response(res).has.status(200)
      end)

      describe("with plugin-configured timeout on route overrides service and", function()
        it("should succeed if response below timeout", function()
          local res = assert(upstream_request("delay1.test"))
          assert.response(res).has.status(200)
        end)

        it("should fail if response exceeds timeout", function()
          local res = assert(upstream_request("delay2.test"))
          assert.response(res).has.status(504)
        end)
      end)

    end)
  end)
end
