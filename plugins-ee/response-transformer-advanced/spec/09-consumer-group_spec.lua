-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-transformer-advanced (ConsumerGroupScoping) [#" .. strategy .. "]", function()
    local admin_client, proxy_client, bp, db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "consumer_groups",
        "consumers",
        "plugins",
      }, { "key-auth", "response-transformer-advanced" })

      local a_cg = "foobar"

      local a_consumer = assert(db.consumers:insert { username = 'username' .. utils.uuid() })

      local a_consumer_group = assert(db.consumer_groups:insert { name = a_cg })

      local a_mapping = {
        consumer       = { id = a_consumer.id },
        consumer_group = { id = a_consumer_group.id },
      }
      assert(db.consumer_group_consumers:insert(a_mapping))

      assert(db.plugins:insert {
        name = "response-transformer-advanced",
        consumer_group = a_consumer_group,
        config = {
          remove = {
            headers = { "x-to-remove" },
          },
        },
      })

      assert(bp.keyauth_credentials:insert {
        key = "a_mouse",
        consumer = { id = a_consumer.id },
      })

      assert(bp.routes:insert({
        hosts = { "test.example.com" },
      }))

      assert(bp.plugins:insert({
        name = "key-auth",
      }))

      assert(helpers.start_kong({
        database     = strategy,
        plugins      = "bundled,response-transformer-advanced",
        nginx_conf   = "spec/fixtures/custom_nginx.template",
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
      assert(db.consumer_groups)
      assert(db.consumer_group_consumers)
      assert(db.consumer_group_plugins)
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong()
    end)

    it("verify that the plugin triggers correctly", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "test.example.com",
          ["apikey"] = "a_mouse",
          ["x-to-remove"] = "true",
        }
      })
      assert.response(res).has.status(200)
      assert.response(res).has.no.header("x-to-remove")
    end)
  end)
end
