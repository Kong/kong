-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: request-termination (integration) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local consumer, a_consumer_group

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local a_cg = "foobar"

      local a_consumer = assert(db.consumers:insert { username = 'username' .. utils.uuid() })

      a_consumer_group = assert(db.consumer_groups:insert { name = a_cg })

      local a_mapping = {
        consumer       = { id = a_consumer.id },
        consumer_group = { id = a_consumer_group.id },
      }
      assert(db.consumer_group_consumers:insert(a_mapping))

      assert(bp.keyauth_credentials:insert {
        key = "a_mouse",
        consumer = { id = a_consumer.id },
      })


      bp.routes:insert({
        hosts = { "api1.request-termination.test" },
      })

      bp.plugins:insert {
        name = "key-auth",
      }

      consumer = bp.consumers:insert {
        username = "bob",
      }

      bp.keyauth_credentials:insert {
        key      = "kong",
        consumer = { id = consumer.id },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        license_path = "spec-ee/fixtures/mock_license.json",
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

    it("can be applied on a consumer", function()
      -- add the plugin to a consumer
      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/plugins",
        headers = {
          ["Content-type"] = "application/json",
        },
        body    = {
          name        = "request-termination",
          consumer = { id = consumer.id },
        },
      })
      assert.response(res).has.status(201)

      -- verify access being blocked
      helpers.wait_until(function()
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "api1.request-termination.test",
            ["apikey"] = "kong",
          },
        })
        return pcall(function()
          assert.response(res).has.status(503)
        end)
      end, 10)
      local body = assert.response(res).has.jsonbody()
      assert.same({ message = "Service unavailable" }, body)
    end)

    it("can be applied on a consumer group", function()
      -- add the plugin to a consumer
      local res = assert(admin_client:send {
        method  = "POST",
        path    = "/plugins",
        headers = {
          ["Content-type"] = "application/json",
        },
        body    = {
          name        = "request-termination",
          consumer_group = { id = a_consumer_group.id },
        },
      })
      assert.response(res).has.status(201)

      -- verify access being blocked
      helpers.wait_until(function()
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "api1.request-termination.test",
            ["apikey"] = "a_mouse",
          },
        })
        return pcall(function()
          assert.response(res).has.status(503)
        end)
      end, 10)
      local body = assert.response(res).has.jsonbody()
      assert.same({ message = "Service unavailable" }, body)
    end)
  end)
end
