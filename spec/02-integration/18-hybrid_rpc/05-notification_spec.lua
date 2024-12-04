local helpers = require "spec.helpers"

local function test_url(path, port, code, headers)
  helpers.wait_until(function()
    local proxy_client = helpers.http_client("127.0.0.1", port)

    local res = proxy_client:send({
      method  = "GET",
      path    = path,
      headers = headers,
    })

    local status = res and res.status
    proxy_client:close()
    if status == code then
      return true
    end
  end, 10)
end

-- register a test rpc service in custom plugin rpc-notification-test
for _, strategy in helpers.each_strategy() do
  describe("Hybrid Mode RPC #" .. strategy, function()

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "clustering_data_planes",
      }) -- runs migrations

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,rpc-notification-test",
        nginx_worker_processes = 4, -- multiple workers
        cluster_rpc = "on",
        cluster_incremental_sync = "off",
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
        plugins = "bundled,rpc-notification-test",
        nginx_worker_processes = 4, -- multiple workers
        cluster_rpc = "on",
        cluster_incremental_sync = "off",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("notification works", function()
      it("in custom plugin", function()
        local admin_client = helpers.admin_client(10000)
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:post("/services", {
          body = { name = "service-001", url = "https://127.0.0.1:15556/request", },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        res = assert(admin_client:post("/services/service-001/routes", {
          body = { paths = { "/001" }, },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        res = assert(admin_client:post("/plugins", {
          body = { name = "rpc-notification-test", },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, res)

        test_url("/001", 9002, 200)

        -- wait notification running
        ngx.sleep(0.2)

        -- cp logs
        helpers.pwait_until(function()
          assert.logfile().has.line(
            "notification is hello", true)
          assert.logfile().has.line(
            "[rpc] notifying kong.test.notification(node_id:", true)
          assert.logfile().has.line(
            "[rpc] notification has no response", true)
          return true
        end, 10)

        -- dp logs
        helpers.pwait_until(function()
          assert.logfile("servroot2/logs/error.log").has.line(
            "[rpc] notifying kong.test.notification(node_id: control_plane) via local", true)
          assert.logfile("servroot2/logs/error.log").has.line(
            "notification is world", true)
          assert.logfile("servroot2/logs/error.log").has.line(
            "[rpc] notification has no response", true)
          return true
        end, 10)

      end)
    end)
  end)
end -- for _, strategy
