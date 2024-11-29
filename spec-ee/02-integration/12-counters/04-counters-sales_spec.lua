-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Sales counters with db: #" .. strategy, function()

    setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "services",
        "rbac_users",
        "consumers",
        "workspace_entity_counters",
      })

      assert(bp.workspaces:insert({
        name = "ws-1",
      }))

      assert(bp.workspaces:insert({
        name = "ws-2",
      }))

      assert(helpers.start_kong({
        database = strategy,
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    describe("/licenses/report", function()
      it("should return the number of rbac_users", function()
        local admin_api = require "spec.fixtures.admin_api"
        admin_api.set_prefix("")
        assert(admin_api.services)
        assert(admin_api.rbac_users)

        local services = {}
        for i = 1, 10 do
          services[i] = admin_api.services:insert {
            name = "service-" .. i,
            url = "http://127.0.0.1",
          }
        end

        local rbac_users = {}
        for i = 1, 10 do
          rbac_users[i] = admin_api.rbac_users:insert {
            name = "rbac_user-" .. i,
            user_token = "rbac_user-" .. i,
          }
        end

        helpers.wait_until(function()
          local client = helpers.admin_client()
          local res = client:send({
            method = "GET",
            path = "/license/report",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          return json.rbac_users == 10 and json.services_count == 10
        end)

        for i = 1, 10 do
          admin_api.rbac_users:remove({ id = rbac_users[i].id })
        end

        for i = 1, 10 do
          admin_api.services:remove({ id = services[i].id })
        end

        helpers.wait_until(function()
          local client = helpers.admin_client()
          local res = client:send({
            method = "GET",
            path = "/license/report",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          return json.rbac_users == 0 and json.services_count == 0
        end)
      end)

      it("should return the number of consumers", function()
        local admin_api = require "spec.fixtures.admin_api"
        admin_api.set_prefix("")
        assert(admin_api.consumers)

        local consumers = {}
        for i = 1, 10 do
          consumers[i] = admin_api.consumers:insert {
            username = "username-" .. i,
            custom_id = "custom_id" .. i,
          }
        end

        helpers.wait_until(function()
          local client = helpers.admin_client()
          local res = client:send({
            method = "GET",
            path = "/license/report",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          return json.consumers_count == 10
        end)
        for i = 1, 10 do
          admin_api.consumers:remove({ id = consumers[i].id })
        end

        helpers.wait_until(function()
          local client = helpers.admin_client()
          local res = client:send({
            method = "GET",
            path = "/license/report",
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          return json.consumers_count == 0
        end)
      end)
    end)
  end)
end
