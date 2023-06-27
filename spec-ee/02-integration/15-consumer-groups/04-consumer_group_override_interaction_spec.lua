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
    local db, bp, admin_client, proxy_client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "rate-limiting-advanced" })
      assert(bp.routes:insert({
        hosts = { "test1.example.com" },
      }))

      assert(helpers.start_kong({
        nginx_conf   = "spec/fixtures/custom_nginx.template",
        database     = strategy,
        plugins      = "bundled," .. "rate-limiting-advanced",
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
      admin_client = assert(helpers.admin_client())
      assert(db.consumer_groups)
      assert(db.consumer_group_consumers)
      assert(db.consumer_group_plugins)
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
      if admin_client then
        admin_client:close()
        proxy_client:close()
      end
    end)
    local function insert_entities()
      local a_cg = "a_test_group_" .. utils.uuid()
      local b_cg = "b_test_group_" .. utils.uuid()

      local a_consumer = assert(db.consumers:insert { username = 'username' .. utils.uuid() })
      local b_consumer = assert(db.consumers:insert { username = 'username' .. utils.uuid() })

      local a_consumer_group = assert(db.consumer_groups:insert { name = a_cg })
      local b_consumer_group = assert(db.consumer_groups:insert { name = b_cg })

      local a_mapping = {
        consumer       = { id = a_consumer.id },
        consumer_group = { id = a_consumer_group.id },
      }
      assert(db.consumer_group_consumers:insert(a_mapping))

      local b_mapping = {
        consumer       = { id = b_consumer.id },
        consumer_group = { id = b_consumer_group.id },
      }
      assert(db.consumer_group_consumers:insert(b_mapping))

      bp.key_auth_plugins:insert()

      assert(bp.keyauth_credentials:insert {
        key = "a_mouse",
        consumer = { id = a_consumer.id },
      })
      assert(bp.keyauth_credentials:insert {
        key = "b_mouse",
        consumer = { id = b_consumer.id },
      })
      return a_consumer_group, b_consumer_group
    end

    it("validate override precedence", function()
      local a_consumer_group, b_consumer_group = insert_entities()

      local default_config = {
        window_size = { 100 },
        limit = { 100 },
        enforce_consumer_groups = true,
        consumer_groups = { a_consumer_group.name, b_consumer_group.name }
      }
      -- scope a plugin to a consumer_group
      assert.res_status(201, assert(admin_client:send {
        method = "POST",
        path = "/consumer_groups/" .. a_consumer_group.id .. "/plugins",
        body = {
          name = "rate-limiting-advanced",
          config = default_config,
        },
        headers = {
          ["Content-Type"] = "application/json",
        } }))

      local a_override_config = {
        window_size = { 10 },
        limit = { 10 },
      }
      -- defining an override for a_consumer_group
      assert.res_status(201, assert(admin_client:send {
        method = "PUT",
        path = "/consumer_groups/" .. a_consumer_group.id .. "/overrides/plugins/rate-limiting-advanced",
        body = {
          config = a_override_config,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))

      local b_override_config = {
        window_size = { 20 },
        limit = { 20 },
      }
      -- defining an override for b_consumer_group
      assert.res_status(201, assert(admin_client:send {
        method = "PUT",
        path = "/consumer_groups/" .. b_consumer_group.id .. "/overrides/plugins/rate-limiting-advanced",
        body = {
          config = b_override_config,
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      }))

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "test1.example.com",
          ["apikey"] = "a_mouse"
        }
      })
      -- Expect that the override for a_consumer_group applies as it was defined
      -- as the first item in the `consumer_groups` array
      assert.response(res).has.header("X-RateLimit-Limit-10")
    end)
  end)
end
