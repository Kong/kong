local helpers = require "spec.helpers"
local cjson = require("cjson.safe")

-- register a test rpc service in custom plugin rpc-batch-test
for _, strategy in helpers.each_strategy() do
  describe("Hybrid Mode RPC #" .. strategy, function()

    lazy_setup(function()
      helpers.get_db_utils(strategy, { "routes", "services" })

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_rpc = "on",
        plugins = "bundled,rpc-batch-test",
        cluster_rpc_sync = "off",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_rpc = "on",
        plugins = "bundled,rpc-batch-test",
        cluster_rpc_sync = "off",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("batch works", function()
      it("DP calls CP via batching", function()
        local admin_client = helpers.admin_client(10000)
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:post("/services", {
          body = { name = "mockbin-service", url = "https://127.0.0.1:15556/request", },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        res = assert(admin_client:post("/services/mockbin-service/routes", {
          body = { paths = { "/" }, },
          headers = {["Content-Type"] = "application/json"}
        }))
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        local route_id = json.id

        -- add a plugin for route
        res = assert(admin_client:post("/routes/" .. route_id .. "/plugins", {
          body = { name = "rpc-batch-test" },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        helpers.wait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)

          res = proxy_client:send({
            method  = "GET",
            path    = "/",
          })

          local status = res and res.status
          proxy_client:close()
          if status == 200 then
            return true
          end
        end, 10)

        helpers.pwait_until(function()
          assert.logfile().has.line(
            "[rpc] got batch RPC call: 1", true)
          assert.logfile().has.line(
            "kong.test.batch called: world", true)

          assert.logfile("servroot2/logs/error.log").has.line(
            "[rpc] sent batch RPC call: 1", true)
          assert.logfile("servroot2/logs/error.log").has.line(
            "[rpc] got batch RPC call: 1", true)
          assert.logfile("servroot2/logs/error.log").has.line(
            "kong.test.batch called: hello world", true)

          return true
        end, 10)

        helpers.pwait_until(function()
          assert.logfile("servroot2/logs/error.log").has.line(
            "[rpc] sent batch RPC call: 2", true)

          assert.logfile().has.line(
            "[rpc] got batch RPC call: 2", true)
          assert.logfile().has.line(
            "kong.test.batch called: kong", true)
          assert.logfile().has.line(
            "kong.test.batch called: gateway", true)

          return true
        end, 10)
      end)
    end)
  end)
end -- for _, strategy
