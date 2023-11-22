-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local utils   = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  describe("proxy-cache respects consumer-group assignments: #" .. strategy, function()
    local client
    local admin_client
    local manager_group
    local a_consumer
    local bp, db


    setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "consumer_groups",
        "consumers",
        "plugins",
      }, { "key-auth", "proxy-cache" })

      local a_cg = "manager"
      local b_cg = "employee"

      a_consumer = assert(db.consumers:insert { username = 'username' .. utils.uuid() })

      manager_group = assert(db.consumer_groups:insert { name = a_cg })
      local employee_group = assert(db.consumer_groups:insert { name = b_cg })

      local a_mapping = {
        consumer       = { id = a_consumer.id },
        consumer_group = { id = manager_group.id },
      }
      local b_mapping = {
        consumer       = { id = a_consumer.id },
        consumer_group = { id = employee_group.id },
      }
      assert(db.consumer_group_consumers:insert(a_mapping))
      assert(db.consumer_group_consumers:insert(b_mapping))

      assert(bp.keyauth_credentials:insert {
        key = "a_mouse",
        consumer = { id = a_consumer.id },
      })

      local route = assert(bp.routes:insert({
        hosts = { "route-1.com" },
      }))

      assert(bp.plugins:insert({
        name = "key-auth",
      }))

      assert(bp.plugins:insert {
        name = "proxy-cache",
        route = { id = route.id },
        consumer = a_consumer,
        config = {
          strategy = "memory",
          content_type = { "text/plain", "application/json" },
          memory = {
            dictionary_name = "kong",
          },
        },
      })

      assert(helpers.start_kong {
        database     = strategy,
        plugins      = "proxy-cache, key-auth",
        nginx_conf   = "spec/fixtures/custom_nginx.template",
        license_path = "spec-ee/fixtures/mock_license.json",
      })

      admin_client = helpers.admin_client()
      client = helpers.proxy_client()
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end
      if client then
        client:close()
      end
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("Consumer Group changes have an effect on cache-key creation", function()
      local cache_key, cache_key2

      setup(function()
        -- prime cache entries
        local res_1 = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            Host = "route-1.com",
            ApiKey = "a_mouse",
          },
        })

        assert.res_status(200, res_1)
        assert.same("Miss", res_1.headers["X-Cache-Status"])
        cache_key = res_1.headers["X-Cache-Key"]


        res_1 = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
            ApiKey = "a_mouse",
          },
        })

        assert.res_status(200, res_1)
        assert.same("Hit", res_1.headers["X-Cache-Status"])
        cache_key2 = res_1.headers["X-Cache-Key"]
        assert.same(cache_key, cache_key2)
      end)

      it("registers when consumer-groups change", function()
        -- verify that the pre-warmed cache still works
        local res_1 = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
            ApiKey = "a_mouse",
          },
        })

        assert.res_status(200, res_1)
        assert.same("Hit", res_1.headers["X-Cache-Status"])

        -- now remove the consumer from one of his groups
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/consumers/" .. a_consumer.id .. "/consumer_groups/" .. manager_group.id
        })
        assert.res_status(204, res)

        -- fire the same request again and expect no `Hit`
        -- as the underlying cache key has changed (consumer-group mapping changed)
        local res_2 = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
            ApiKey = "a_mouse",
          },
        })
        assert.res_status(200, res_2)
        assert.same("Miss", res_2.headers["X-Cache-Status"])

        -- Firing again. Now, we expect a `Hit` again
        local res_3 = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
            ApiKey = "a_mouse",
          },
        })
        assert.res_status(200, res_3)
        assert.same("Hit", res_3.headers["X-Cache-Status"])
      end)
    end)
  end)
end
