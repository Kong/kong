local helpers = require "spec.helpers"
local cjson = require("cjson.safe")
local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS

for _, strategy in helpers.each_strategy() do
describe("CP disabled Sync RPC #" .. strategy, function()
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
      nginx_worker_processes = 2, -- multiple workers

      cluster_rpc = "on", -- CP ENABLE rpc
      cluster_rpc_sync = "off", -- CP DISABLE rpc sync
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
      nginx_worker_processes = 2, -- multiple workers

      cluster_rpc = "on", -- DP ENABLE rpc
      cluster_rpc_sync = "on", -- DP ENABLE rpc sync
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong("servroot2")
    helpers.stop_kong()
  end)

  after_each(function()
    helpers.clean_logfile("servroot2/logs/error.log")
    helpers.clean_logfile()
  end)

  describe("works", function()
    it("shows DP status", function()
      helpers.wait_until(function()
        local admin_client = helpers.admin_client()
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:get("/clustering/data-planes"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        for _, v in pairs(json.data) do
          if v.ip == "127.0.0.1" then
            assert.near(14 * 86400, v.ttl, 3)
            assert.matches("^(%d+%.%d+)%.%d+", v.version)
            assert.equal(CLUSTERING_SYNC_STATUS.NORMAL, v.sync_status)
            return true
          end
        end
      end, 10)

      -- cp will not run rpc
      assert.logfile().has.no.line("[rpc]", true)

      -- dp will not run rpc too
      assert.logfile("servroot2/logs/error.log").has.line(
        "rpc sync is disabled in CP")
      assert.logfile("servroot2/logs/error.log").has.line(
        "sync v1 is enabled due to rpc sync can not work.")
    end)
  end)

  describe("sync works", function()
    it("proxy on DP follows CP config", function()
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
    end)
  end)
end)


describe("CP disables Sync RPC with older data planes #" .. strategy, function()
  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "clustering_data_planes",
    }, {
      "older-version",
      "error-generator",
      "error-generator-last",
      "error-handler-log",
    })

    assert(helpers.start_kong({
      role = "control_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      database = strategy,
      prefix = "servroot2",
      cluster_listen = "127.0.0.1:9005",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      nginx_worker_processes = 2, -- multiple workers

      cluster_rpc = "on", -- CP ENABLE rpc
      cluster_rpc_sync = "on", -- CP ENABLE rpc sync
    }))

    assert(helpers.start_kong({
      role = "data_plane",
      database = "off",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_control_plane = "127.0.0.1:9005",
      proxy_listen = "0.0.0.0:9002",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      nginx_worker_processes = 2, -- multiple workers

      plugins = "older-version,error-generator,error-generator-last,error-handler-log",
      cluster_rpc = "on", -- DP ENABLE rpc
      cluster_rpc_sync = "on", -- DP ENABLE rpc sync
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    helpers.stop_kong("servroot2")
  end)

  after_each(function()
    helpers.clean_logfile()
    helpers.clean_logfile("servroot2/logs/error.log")
  end)

  it("fallbacks to sync v1", function()
    helpers.wait_until(function()
      local admin_client = helpers.admin_client()
      finally(function()
        admin_client:close()
      end)

      local res = assert(admin_client:get("/clustering/data-planes"))
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      for _, v in pairs(json.data) do
        if v.ip == "127.0.0.1" then
          assert.near(14 * 86400, v.ttl, 3)
          assert.matches("^(%d+%.%d+)%.%d+", v.version)
          assert.equal(CLUSTERING_SYNC_STATUS.NORMAL, v.sync_status)
          return true
        end
      end
    end, 10)

    -- cp will not run rpc
    assert.logfile("servroot2/logs/error.log").has.no.line("[rpc]", true)
    assert.logfile("servroot2/logs/error.log").has.line(
      "disabling kong.sync.v2 because the data plane is older than the control plane", true)

    -- dp will not run rpc too
    assert.logfile().has.line("rpc sync is disabled in CP")
    assert.logfile().has.line("sync v1 is enabled due to rpc sync can not work.")
  end)
end)
end -- for _, strategy
