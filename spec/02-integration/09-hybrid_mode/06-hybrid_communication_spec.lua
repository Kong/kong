local helpers = require "spec.helpers"
local cjson = require("cjson.safe")
local pl_file = require("pl.file")
local TEST_CONF = helpers.test_conf


for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync works with #" .. strategy .. " backend", function()
    local client

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, {
        "hybrid-comm-tests",
      }) -- runs migrations
      assert(db:truncate())

      local service = bp.services:insert {
        name     = "service",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route1 = bp.routes:insert {
        service = { id = service.id },
        paths   = { "/route1", },
      }

      bp.plugins:insert {
        name    = "hybrid-comm-tests",
        route   = { id = route1.id },
        config  = {},
      }

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_v2 = "on",
        plugins = "bundled,hybrid-comm-tests",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        cluster_v2 = "on",
        plugins = "bundled,hybrid-comm-tests",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client(nil, 9002)
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("pure message", function()
      it("can be sent back and forth between CP and DP", function()
        local res
        helpers.wait_until(function()
          if client then
            client:close()
          end
          client = helpers.proxy_client(nil, 9002)

          res = client:send {
            method = "GET",
            path = "/route1",
          }

          return res and res.status == 200
        end, 5)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        helpers.wait_until(function()
          local logs = pl_file.read(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log)
          return logs:find("[hybrid-comm-tests] src = " .. json.node_id .. ", dest = control_plane, topic = hybrid_comm_test, message = hello world!", nil, true)
        end, 5)

        helpers.wait_until(function()
          local logs = pl_file.read("servroot2" .. "/" .. TEST_CONF.proxy_error_log)
          return logs:find("[hybrid-comm-tests] src = control_plane" .. ", dest = " .. json.node_id .. ", topic = hybrid_comm_test_resp, message = hello world!", nil, true)
        end, 5)
      end)
    end)
  end)
end
