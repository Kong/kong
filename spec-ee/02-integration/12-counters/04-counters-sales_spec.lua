local helpers = require "spec.helpers"
local kong_counters_sales = require "kong.counters.sales"

for _, strategy in helpers.each_strategy() do
  describe("Sales counters with db: #" .. strategy, function()
    local counters, bp, db

    setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "services",
      })

      assert(helpers.start_kong({
        database = strategy,
      }))

      local counters_strategy = require("kong.counters.sales.strategies." .. strategy):new(db)
      counters = kong_counters_sales.new({ strategy = counters_strategy })
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
      assert(db:truncate())
    end)

    describe("get_workspace_entity_counters_count()", function()
      it("should return the number of services", function()
        local services_count

        for i = 1, 10 do
          bp.services:insert {
            name = "service-" .. i,
            url = "http://httpbin.org",
          }
        end

        services_count = counters:get_license_report().services_count
        assert.equals(10, services_count)

        assert(db:truncate())

        services_count = counters:get_license_report().services_count
        assert.equals(0, services_count)
      end)

      it("should return the number of rbac_users", function()
        local rbac_users

        for i = 1, 10 do
          db.rbac_users:insert {
            name = "rbac_user-" .. i,
            user_token = "rbac_user-" .. i,
          }
        end

        rbac_users = counters:get_license_report().rbac_users
        assert.equals(10, rbac_users)

        assert(db:truncate())

        rbac_users = counters:get_license_report().rbac_users
        assert.equals(0, rbac_users)
      end)

      it("accounts for multiple workspaces", function()
        local services_count, rbac_users

        local ws1 = bp.workspaces:insert {
          name = "ws1"
        }

        local ws2 = bp.workspaces:insert {
          name = "ws2"
        }

        for i = 1, 10 do
          bp.services:insert_ws ({
            name = "service-" .. i .. "-ws1",
            url = "http://httpbin.org",
          }, ws1)
          bp.rbac_users:insert_ws ({
            name = "rbac_user-" .. i .. "-ws1",
            user_token = "rbac_user-" .. i .. "-ws1",
          }, ws1)
        end

        for i = 1, 10 do
          bp.services:insert_ws ({
            name = "service-" .. i .. "-ws2",
            url = "http://httpbin.org",
          }, ws2)
          bp.rbac_users:insert_ws ({
            name = "rbac_user-" .. i .. "-ws2",
            user_token = "rbac_user-" .. i .. "-ws2",
          }, ws2)
        end

        services_count = counters:get_license_report().services_count
        assert.equals(20, services_count)
        rbac_users = counters:get_license_report().rbac_users
        assert.equals(20, rbac_users)

        assert(db:truncate())

        services_count = counters:get_license_report().services_count
        assert.equals(0, services_count)
        rbac_users = counters:get_license_report().rbac_users
        assert.equals(0, rbac_users)
      end)
    end)
  end)
end
