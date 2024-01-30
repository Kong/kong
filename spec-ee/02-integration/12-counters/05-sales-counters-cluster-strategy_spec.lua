-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
for _, strategy in helpers.each_strategy() do
  local hybrid_describe = (strategy ~= "cassandra") and describe or pending
  hybrid_describe("Hybrid sales counter works with #" .. strategy .. " backend", function()
    describe("sync works", function()
      lazy_setup(function()
        helpers.get_db_utils(strategy, {
          "routes",
          "services",
        }) -- runs migrations

        assert(helpers.start_kong({
          role = "control_plane",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
          database = strategy,
          db_update_frequency = 0.1,
          db_update_propagation = 0.1,
          cluster_listen = "127.0.0.1:9005",
          cluster_telemetry_listen = "127.0.0.1:9006",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        assert(helpers.start_kong({
          role = "data_plane",
          database = "off",
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
          cluster_control_plane = "127.0.0.1:9005",
          cluster_telemetry_endpoint = "127.0.0.1:9006",
          proxy_listen = "0.0.0.0:9002",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2")
        helpers.stop_kong()
      end)

      -- this is copied from spec/02-integration/09-hybrid-mode/01-sync_spec.lua
      it("cluster counter flush to CP telemetry", function()

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

        assert.res_status(201, res)

        helpers.pwait_until(function()
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
        end, 30)

        helpers.wait_until(function()
            local pl_file = require "pl.file"
            local s = pl_file.read("servroot2/logs/error.log")
            if not s:match("telemetry websocket is connected") then
              return
            end
            if not s:match("flush %d+ bytes to CP") then
              return
            end
  
            return true
        end, 10)
      end)

      it("proxy on DP do not flush to CP telemetry when cluster_telemetry_endpoint is disabled", function()
        local pl_file = require "pl.file"
        pl_file.delete("servroot2/logs/error.log")
        
        assert(helpers.restart_kong({
            role = "data_plane",
            database = "off",
            prefix = "servroot2",
            cluster_cert = "spec/fixtures/kong_clustering.crt",
            cluster_cert_key = "spec/fixtures/kong_clustering.key",
            lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
            cluster_control_plane = "127.0.0.1:9005",
            cluster_telemetry_endpoint = "NONE",
            proxy_listen = "0.0.0.0:9002",
          }))


        helpers.pwait_until(function()
          local proxy_client = helpers.http_client("127.0.0.1", 9002)

          local res = proxy_client:send({
            method  = "GET",
            path    = "/",
          })

          local status = res and res.status
          proxy_client:close()
          if status == 200 then
            return true
          end
        end, 30)

        helpers.wait_until(function()
            local pl_file = require "pl.file"
            local s = pl_file.read("servroot2/logs/error.log")
            if s:match("[messaging-utils] cleaned up 1 unflushed buffer") then
              return false
            end

            if s:match("telemetry websocket is connected") then
              return false
            end

            if s:match("flush %d+ bytes to CP") then
              return false
            end

            if not s:match("loading off strategy") then
              return false
            end

            if not s:match("cluster_telemetry_endpoint is NONE, bypass initializing strategy") then
              return false
            end

            return true
        end, 10)
      end)
    end)
  end)
end
