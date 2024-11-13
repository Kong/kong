local helpers = require "spec.helpers"
local cjson = require("cjson.safe")
local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS

for _, dedicated in ipairs { "on", "off" } do
for _, strategy in helpers.each_strategy() do

describe("DP diabled Incremental Sync RPC #" .. strategy, function()

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

      cluster_incremental_sync = "on", -- ENABLE incremental sync
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

      cluster_incremental_sync = "off", -- DISABLE incremental sync

      dedicated_config_processing = dedicated, -- privileged agent
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

  describe("works when dedicated_config_processing = " .. dedicated, function()
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

      -- dp lua-resty-events should work well with or without privileged_agent
      assert.logfile("servroot2/logs/error.log").has.line(
        "lua-resty-events enable_privileged_agent is " .. tostring(dedicated == "on"), true)
    end)
  end)

  describe("sync works when dedicated_config_processing = " .. dedicated, function()
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
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

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

end -- for _, strategy
end -- for _, dedicated
