local helpers             = require "spec.helpers"
local kong_counters_sales = require "kong.counters.sales"
local workspaces          = require "kong.workspaces"

for _, strategy in helpers.each_strategy() do
  describe("Sales counters with db: #" .. strategy, function()
    local counters, bp, db
    local ws1, ws2

    setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "services",
      })

      ws1 = assert(bp.workspaces:insert({
        name = "ws-1",
      }))

      ws2 = assert(bp.workspaces:insert({
        name = "ws-2",
      }))

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

        workspaces.run_with_ws_scope({ ws1 }, function ()
          for i = 1, 10 do
            bp.services:insert {
              name = "ws-1-service-" .. i,
              url = "http://httpbin.org",
            }
          end
        end)

        workspaces.run_with_ws_scope({ ws2 }, function ()
          for i = 1, 10 do
            bp.services:insert {
              name = "ws-2-service-" .. i,
              url = "http://httpbin.org",
            }
          end
        end)

        services_count = counters:get_license_report().services_count
        assert.equals(20, services_count)
      end)

      it("should return the number of rbac_users", function()
        local rbac_users

        workspaces.run_with_ws_scope({ ws1 }, function ()
          for i = 1, 5 do
            db.rbac_users:insert {
              name = "ws-1-rbac_user-" .. i,
              user_token = "ws-1-rbac_user-" .. i,
            }
          end
        end)

        workspaces.run_with_ws_scope({ ws2 }, function ()
          for i = 1, 10 do
            db.rbac_users:insert {
              name = "ws-2-rbac_user-" .. i,
              user_token = "ws-2-rbac_user-" .. i,
            }
          end
        end)

        rbac_users = counters:get_license_report().rbac_users
        assert.equals(15, rbac_users)
      end)
    end)
  end)
end
