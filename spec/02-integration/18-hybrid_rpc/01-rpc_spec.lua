local helpers = require "spec.helpers"
local cjson = require("cjson.safe")

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
        cluster_rpc = "on",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        cluster_rpc = "on",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("status API", function()
      -- TODO: remove this test once cluster RPC is GA
      it("no DR RPC capabilities exist", function()
        -- This should time out, we expect no RPC capabilities
        local status = pcall(helpers.wait_until, function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:get("/clustering/data-planes"))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          for _, v in pairs(json.data) do
            if v.ip == "127.0.0.1" and v.rpc_capabilities and #v.rpc_capabilities ~= 0 then
              table.sort(v.rpc_capabilities)
              assert.near(14 * 86400, v.ttl, 3)
              assert.same({ "kong.debug.log_level.v1", }, v.rpc_capabilities)
              return true
            end
          end
        end, 10)
        assert.is_false(status)
      end)

      pending("shows DP RPC capability status", function()
        helpers.wait_until(function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:get("/clustering/data-planes"))
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          for _, v in pairs(json.data) do
            if v.ip == "127.0.0.1" and v.rpc_capabilities and #v.rpc_capabilities ~= 0 then
              table.sort(v.rpc_capabilities)
              assert.near(14 * 86400, v.ttl, 3)
              assert.same({ "kong.debug.log_level.v1", }, v.rpc_capabilities)
              return true
            end
          end
        end, 10)
      end)
    end)
  end)
end
