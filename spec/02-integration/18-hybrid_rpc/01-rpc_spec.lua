local helpers = require "spec.helpers"
local cjson = require("cjson.safe")
local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS

-- we need incremental sync to verify rpc
for _, inc_sync in ipairs { "on" } do
for _, strategy in helpers.each_strategy() do
  describe("Hybrid Mode RPC #" .. strategy .. " inc_sync=" .. inc_sync, function()

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
        cluster_rpc = "on",
        cluster_incremental_sync = inc_sync, -- incremental sync
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
        cluster_incremental_sync = inc_sync, -- incremental sync
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("status API", function()
      it("shows DP RPC capability status", function()
        helpers.wait_until(function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:get("/clustering/data-planes"))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert(json)

          -- TODO: perhaps need a new test method
          for _, v in pairs(json.data) do
            if v.ip == "127.0.0.1" and v.rpc_capabilities and #v.rpc_capabilities ~= 0 then
              assert.near(14 * 86400, v.ttl, 3)
              assert.matches("^(%d+%.%d+)%.%d+", v.version)
              assert.equal(CLUSTERING_SYNC_STATUS.NORMAL, v.sync_status)

              local reg = [[^(\d+)\.(\d+)]]
              local m = assert(ngx.re.match(v.version, reg))
              assert(tonumber(m[1]) >= 3)
              assert(tonumber(m[2]) >= 9)

              -- check the available rpc service
              table.sort(v.rpc_capabilities)
              assert.same("kong.sync.v2", v.rpc_capabilities[1])
              return true
            end
          end
        end, 10)
      end)
    end)
  end)
end -- for _, strategy
end -- for inc_sync
