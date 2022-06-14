-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local bu            = require "spec.fixtures.balancer_utils"
local cjson         = require "cjson"
local helpers       = require "spec.helpers"
local https_server  = helpers.https_server
local utils         = require "kong.tools.utils"


for _, consistency in ipairs(bu.consistencies) do
  for _, strategy in helpers.each_strategy() do
    describe("Manipulate upstreams #" .. consistency, function()
      lazy_setup(function()
        bu.get_db_utils_for_dc_and_admin_api(strategy, {
          "routes",
          "services",
          "plugins",
          "upstreams",
          "targets",
        })

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          db_update_frequency = 0.1,
          worker_consistency = consistency,
          worker_state_update_frequency = bu.CONSISTENCY_FREQ,
          nginx_worker_processes = 2,
        }))

      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("Add, remove and add again upstream in non-default workspace", function()
        local admin_client = assert(helpers.admin_client())

        -- create workspace
        local res = assert(admin_client:post("/workspaces", {
          body   = {
            name = "its-a-workspace",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        local ws_id = json.id
        assert.is_true(utils.is_valid_uuid(ws_id))

        -- add an upstream
        res = assert(admin_client:post("/its-a-workspace/upstreams", {
          body = {
            name = "an-upstream"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- add a target
        local a_port = bu.gen_port()
        local a_target = "127.0.0.1:" .. a_port
        res = assert(admin_client:post("/its-a-workspace/upstreams/an-upstream/targets", {
          body = {
            target = a_target
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- add a service
        res = assert(admin_client:post("/its-a-workspace/services", {
          body = {
            name = "a-service",
            host = "an-upstream"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- add a route
        res = assert(admin_client:post("/its-a-workspace/services/a-service/routes", {
          body = {
            name = "a-route",
            hosts = {"a-host"},
            paths = {"/"},
            preserve_host = false,
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- if consistency is eventual, wait for update
        if consistency == "eventual" then
          ngx.sleep(bu.CONSISTENCY_FREQ * 2)
        end

        -- start server
        local a_server = https_server.new(a_port, "127.0.0.1")
        a_server:start()

        -- test
        local requests = 100
        local oks = bu.client_requests(requests, "a-host")
        assert.are.equal(requests, oks)

        -- create another ones
        -- add another upstream
        res = assert(admin_client:post("/its-a-workspace/upstreams", {
          body = {
            name = "another-upstream"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- add another target
        local another_port = bu.gen_port()
        local another_target = "127.0.0.1:" .. another_port
        res = assert(admin_client:post("/its-a-workspace/upstreams/another-upstream/targets", {
          body = {
            target = another_target
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- create another service
        res = assert(admin_client:post("/its-a-workspace/services", {
          body = {
            name = "another-service",
            host = "another-upstream"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- add another route
        res = assert(admin_client:post("/its-a-workspace/services/another-service/routes", {
          body = {
            name = "another-route",
            hosts = {"a-host"},
            paths = {"/"},
            preserve_host = false,
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- delete previous target, route, upstream and service
        local target_path = "/its-a-workspace/upstreams/an-upstream/targets/" .. a_target
        res = assert(admin_client:delete(target_path, {
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(204, res)
        res = assert(admin_client:delete("/its-a-workspace/services/a-service/routes/a-route", {
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(204, res)
        res = assert(admin_client:delete("/its-a-workspace/upstreams/an-upstream", {
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(204, res)
        res = assert(admin_client:delete("/its-a-workspace/services/a-service", {
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(204, res)

        -- if consistency is eventual, wait for update
        if consistency == "eventual" then
          ngx.sleep(bu.CONSISTENCY_FREQ * 2)
        end

        -- start another server
        local another_server = https_server.new(another_port, "127.0.0.1")
        another_server:start()

        -- test
        oks = bu.client_requests(requests, "a-host")
        assert.are.equal(requests, oks)

        -- now go back to first setup
        -- add an upstream
        res = assert(admin_client:post("/its-a-workspace/upstreams", {
          body = {
            name = "an-upstream"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- add a target
        res = assert(admin_client:post("/its-a-workspace/upstreams/an-upstream/targets", {
          body = {
            target = a_target
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- add a service
        res = assert(admin_client:post("/its-a-workspace/services", {
          body = {
            name = "a-service",
            host = "an-upstream"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- add a route
        res = assert(admin_client:post("/its-a-workspace/services/a-service/routes", {
          body = {
            name = "a-route",
            hosts = {"a-host"},
            paths = {"/"},
            preserve_host = false,
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        -- delete previous target, route, upstream and service
        target_path = "/its-a-workspace/upstreams/another-upstream/targets/" .. another_target
        res = assert(admin_client:delete(target_path, {
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(204, res)
        res = assert(admin_client:delete("/its-a-workspace/services/another-service/routes/another-route", {
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(204, res)
        res = assert(admin_client:delete("/its-a-workspace/upstreams/another-upstream", {
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(204, res)
        res = assert(admin_client:delete("/its-a-workspace/services/another-service", {
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(204, res)

        -- if consistency is eventual, wait for update
        if consistency == "eventual" then
          ngx.sleep(bu.CONSISTENCY_FREQ * 2)
        end

        -- test
        oks = bu.client_requests(requests, "a-host")
        assert.are.equal(requests, oks)

        local a_count = a_server:shutdown()
        local another_count = another_server:shutdown()

        -- verify
        assert.are.equal(requests * 2, a_count.total)
        assert.are.equal(requests, another_count.total)
      end)

    end)
  end
end
