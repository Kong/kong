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
    local db, bp, admin_client, proxy_client, protected_route, unprotected_route

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "set-consumer-group", "response-transformer" })

      unprotected_route = assert(bp.routes:insert({
        hosts = { "test1.example.com" },
      }))
      protected_route = assert(bp.routes:insert({
        hosts = { "protected.example.com" },
      }))

      assert(helpers.start_kong({
        nginx_conf   = "spec/fixtures/custom_nginx.template",
        database     = strategy,
        plugins      = "bundled," .. "set-consumer-group, " .. "response-transformer",
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
      admin_client = assert(helpers.admin_client())
      assert(db.consumer_groups)
      assert(db.consumer_group_consumers)
      assert(db.consumer_group_plugins)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      if admin_client then
        admin_client:close()
        proxy_client:close()
      end
    end)
    local function insert_entities()
      local a_cg = "a-test-group-" .. utils.uuid()
      local b_cg = "b-test-group-" .. utils.uuid()

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

      -- protect a certain route
      bp.key_auth_plugins:insert({
        route = protected_route
      })

      assert(bp.keyauth_credentials:insert {
        key = "a_mouse",
        consumer = { id = a_consumer.id },
      })
      assert(bp.keyauth_credentials:insert {
        key = "b_mouse",
        consumer = { id = b_consumer.id },
      })

      -- set custom plugin to a route
      -- this plugin will use the client pdk to
      -- set a consumer_group explicitly
      assert.res_status(201, assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "set-consumer-group",
          route = unprotected_route,
          config = {
            group_name = a_consumer_group.name,
            group_id = a_consumer_group.id
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        } }))

      return a_consumer_group, b_consumer_group
    end

    it("check if explicitly set consumer-groups will be recognized by other plugins", function()
      local a_consumer_group = insert_entities()

      -- Verify if custom-plugin was executed when sending requests to the associated route
      assert
          .with_timeout(5)
          .eventually(function()
            local res = proxy_client:send {
              method = "GET",
              path = "/request",
              headers = {
                host = "test1.example.com",
              }
            }
            return res and res.status == 200 and res.headers["SetConsumerGroup-Was-Executed"] == "true"
          end).is_truthy()

      -- Scope a plugin to the newly set consumer-group
      assert.res_status(201, assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "response-transformer",
          consumer_group = { name = a_consumer_group.name },
          config = {
            add = {
              headers = { string.format("%s:true", a_consumer_group.name) }
            }
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        } }))

      -- and verify if it was executed when sending requests against the associated route
      assert
          .with_timeout(5)
          .eventually(function()
            local res = proxy_client:send {
              method = "GET",
              path = "/request",
              headers = {
                host = "test1.example.com",
              }
            }
            return res and res.status == 200 and res.headers[a_consumer_group.name] == "true"
          end).is_truthy()

      -- verify if this plugin gets executed if a consumer that is part of this group
      -- authenticates, when targeting a different route.
      assert
          .with_timeout(5)
          .eventually(function()
            local res = proxy_client:send {
              method = "GET",
              path = "/request",
              headers = {
                host = "protected.example.com",
                apikey = "a_mouse"
              }
            }
            return res and res.status == 200 and res.headers[a_consumer_group.name] == "true"
          end).is_truthy()

      -- verify that a consumer (b_consumer) who is not part of that group, will trigger
      -- the consumer-group scoped plugin execution as he is not part of that group
      -- and does not trigger the custom plugin that sets the consumer-group explicitly.
      assert
          .with_timeout(5)
          .eventually(function()
            local res = proxy_client:send {
              method = "GET",
              path = "/request",
              headers = {
                host = "protected.example.com",
                apikey = "b_mouse"
              }
            }
            return res and res.status == 200 and res.headers[a_consumer_group.name] ~= "true"
          end).is_truthy()
    end)
  end)
end
