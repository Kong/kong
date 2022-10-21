local helpers = require "spec.helpers"
local cjson = require "cjson.safe"


local confs = helpers.get_clustering_protocols()


for cluster_protocol, conf in pairs(confs) do
  for _, strategy in helpers.each_strategy() do
    describe("CP/DP PKI sync works with #" .. strategy .. " backend, protocol " .. cluster_protocol, function()

      lazy_setup(function()
        helpers.get_db_utils(strategy, {
          "routes",
          "services",
        }) -- runs migrations

        assert(helpers.start_kong({
          role = "control_plane",
          legacy_hybrid_protocol = (cluster_protocol == "json (by switch)"),
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          db_update_frequency = 0.1,
          database = strategy,
          cluster_listen = "127.0.0.1:9005",
          nginx_conf = conf,
          -- additional attributes for PKI:
          cluster_mtls = "pki",
          cluster_ca_cert = "spec/fixtures/kong_clustering_ca.crt",
        }))

        assert(helpers.start_kong({
          role = "data_plane",
          legacy_hybrid_protocol = (cluster_protocol == "json (by switch)"),
          nginx_conf = conf,
          database = "off",
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering_client.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering_client.key",
          cluster_control_plane = "127.0.0.1:9005",
          proxy_listen = "0.0.0.0:9002",
          -- additional attributes for PKI:
          cluster_mtls = "pki",
          cluster_server_name = "kong_clustering",
          cluster_ca_cert = "spec/fixtures/kong_clustering.crt",
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
                return true
              end
            end
          end, 5)
        end)
        it("shows DP status (#deprecated)", function()
          helpers.wait_until(function()
            local admin_client = helpers.admin_client()
            finally(function()
              admin_client:close()
            end)

            local res = assert(admin_client:get("/clustering/status"))
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            for _, v in pairs(json) do
              if v.ip == "127.0.0.1" then
                return true
              end
            end
          end, 5)
        end)
      end)

      describe("sync works", function()
        local route_id

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

          route_id = json.id

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

        it("cache invalidation works on config change", function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:send({
            method = "DELETE",
            path   = "/routes/" .. route_id,
          }))
          assert.res_status(204, res)

          helpers.wait_until(function()
            local proxy_client = helpers.http_client("127.0.0.1", 9002)

            res = proxy_client:send({
              method  = "GET",
              path    = "/",
            })

            -- should remove the route from DP
            local status = res and res.status
            proxy_client:close()
            if status == 404 then
              return true
            end
          end, 5)
        end)
      end)
    end)
  end
end
