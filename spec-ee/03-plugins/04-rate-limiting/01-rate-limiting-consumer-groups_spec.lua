-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  describe("Consumer Groups Plugin Scoping and `override` interaction", function()
    local db, bp, proxy_client
    local a_cg = "a_test_group_" .. utils.uuid()

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "rate-limiting" })

      assert(bp.routes:insert({
        hosts = { "test1.example.com" },
      }))

      local a_consumer = assert(db.consumers:insert { username = 'username' .. utils.uuid() })

      local a_consumer_group = assert(db.consumer_groups:insert { name = a_cg })

      local a_mapping = {
        consumer       = { id = a_consumer.id },
        consumer_group = { id = a_consumer_group.id },
      }
      assert(db.consumer_group_consumers:insert(a_mapping))

      bp.key_auth_plugins:insert()

      assert(bp.keyauth_credentials:insert {
        key = "a_mouse",
        consumer = { id = a_consumer.id },
      })

      assert(bp.plugins:insert {
        name = "rate-limiting",
        consumer_group = a_consumer_group,
        config = {
          second = 100,
        }
      })

      assert(helpers.start_kong({
        nginx_conf   = "spec/fixtures/custom_nginx.template",
        database     = strategy,
        plugins      = "bundled," .. "rate-limiting",
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
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
      helpers.stop_kong()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("validate scoping", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test1.example.com",
          ["apikey"] = "a_mouse"
        }
      })
      -- Expect that the limit for the consumer_group is applied
      local rl = assert.response(res).has.header("X-RateLimit-Limit-Second")
      local r2 = assert.response(res).has.header("RateLimit-Limit")
      assert.equal("100", rl)
      assert.equal("100", r2)
    end)
  end)
end
