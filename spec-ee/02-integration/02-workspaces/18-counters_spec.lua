-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local helpers = require "spec.helpers"
local counters = require "kong.workspaces.counters"


for _, strategy in helpers.each_strategy() do
  describe("kong.workspaces.counters #" .. strategy, function()
    describe("entity_counts()", function()
      local bp, db
      local default_ws_id
      local other_ws_id

      lazy_setup(function()
        bp, db = helpers.get_db_utils(strategy)

        default_ws_id = assert(kong.default_workspace)
        bp.consumers:insert({})
        bp.services:insert({})

        local ws = bp.workspaces:insert()
        other_ws_id = ws.id
        local opts = { workspace = ws.id }

        bp.consumers:insert({}, opts)

        local service = bp.services:insert({}, opts)

        bp.routes:insert(
          { hosts = { "test" }, service = service },
          opts
        )

        -- the workspace counter hooks don't get executed in this context, so
        -- we need to explicitly initialize them
        require("kong.workspaces.counters").initialize_counters(db)
      end)

      lazy_teardown(function()
        db:truncate()
      end)

      it("filters counts by workspace id", function()
        local counts, err = counters.entity_counts(default_ws_id)
        assert.is_nil(err)
        assert.same(
          {
            consumers = 1,
            services  = 1,
          },
          counts
        )

        counts, err = counters.entity_counts(other_ws_id)
        assert.is_nil(err)
        assert.same(
          {
            consumers = 1,
            services  = 1,
            routes    = 1,
          },
          counts
        )
      end)

      it("returns all counts when no workspace id is passed", function()
        local counts, err = counters.entity_counts()
        assert.is_nil(err)
        assert.same(
          {
            consumers = 2,
            services  = 2,
            routes    = 1,
          },
          counts
        )
      end)

      describe("delete a service concurrently", function()
        local service
        local service_count

        local count_services = function()
          local client = helpers.admin_client()
          local res    = assert(client:get("/workspaces/default/meta"))
          local body   = assert.res_status(200, res)
          client:close()
          local meta = cjson.decode(body)
          return meta.counts.services
        end

        local delete_service = function(client, id)
          client:delete("/services/" .. id)
          client:close()
        end

        lazy_setup(function()
          assert(helpers.start_kong({
            database = strategy
          }))

          local client = helpers.admin_client()
          local res = client:post("/services", {
            body = {
              protocol = "http",
              host     = "service.test",
            },
            headers = { ["Content-Type"] = 'application/json' },
          })
          local body = assert.res_status(201, res)
          client:close()
          service = cjson.decode(body)

          service_count = count_services()
          print("service count at setup = " .. service_count)
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        it("should count services correctly", function()
          local client_count = 20

          local admin_clients = {}
          for i = 1, client_count do
            admin_clients[i] = helpers.admin_client()
          end

          local threads = {}
          for i = 1, client_count do
            threads[i] = ngx.thread.spawn(delete_service, admin_clients[i], service.id)
          end

          for i = 1, client_count do
            ngx.thread.wait(threads[i])
          end

          print("service count after concurrent deletion = " .. count_services())

          assert.True(count_services() == service_count - 1)
        end)
      end)
    end)
  end)
end
