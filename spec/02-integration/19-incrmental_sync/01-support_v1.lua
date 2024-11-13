local helpers = require "spec.helpers"
local cjson = require("cjson.safe")
local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS

for _, dedicated in ipairs { "on", "off" } do
for _, strategy in helpers.each_strategy() do

describe("Incremental Sync RPC #" .. strategy, function()

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
      cluster_incremental_sync = "on", -- enable incremental sync
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
      nginx_worker_processes = 4, -- multiple workers
      cluster_incremental_sync = "off", -- DISABLE incremental sync
      dedicated_config_processing = dedicated, -- privileged agent
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong("servroot2")
    helpers.stop_kong()
  end)

  describe("status API", function()
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
    end)
  end)

end)

end -- for _, strategy
end -- for _, dedicated
