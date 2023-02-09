-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local pl_file = require "pl.file"

-- unsets kong license env vars and returns a function to restore their values
-- on test teardown
--
-- replace distributions_constants.lua to mock a GA release distribution
local function setup_distribution()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  local tmp_filename = "/tmp/distributions_constants.lua"
  assert(helpers.file.copy("kong/enterprise_edition/distributions_constants.lua", tmp_filename, true))
  assert(helpers.file.copy("spec-ee/fixtures/mock_distributions_constants.lua", "kong/enterprise_edition/distributions_constants.lua", true))

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    end

    if helpers.path.exists(tmp_filename) then
      -- restore and delete backup
      assert(helpers.file.copy(tmp_filename, "kong/enterprise_edition/distributions_constants.lua", true))
      assert(helpers.file.delete(tmp_filename))
    end
  end
end

for _, strategy in helpers.each_strategy() do
  describe("Hybrid vitals works with #" .. strategy .. " backend", function()
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
          vitals = true,
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
          vitals = true,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2")
        helpers.stop_kong()
      end)

      -- this is copied from spec/02-integration/09-hybrid-mode/01-sync_spec.lua
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
      end)

      it("sends back vitals metrics to DP", function()
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

        local admin_client = helpers.admin_client()
        finally(function()
          admin_client:close()
        end)

        helpers.pwait_until(function()
          local res = assert(admin_client:send({
            path   = "/vitals/nodes?interval=seconds",
          }))
          assert.res_status(200, res)
          local body = assert(res:read_body())
          local metrics = cjson.decode(body)

          if metrics.stats then
            metrics = metrics.stats
            --[[
              {
                "meta": {
                    ...
                  },
                  "stat_labels": [
                    "cache_datastore_hits_total",
                    "cache_datastore_misses_total",
                    "latency_proxy_request_min_ms",
                    "latency_proxy_request_max_ms",
                    "latency_upstream_min_ms",
                    "latency_upstream_max_ms",
                    "requests_proxy_total",
                    "latency_proxy_request_avg_ms",
                    "latency_upstream_avg_ms"
                  ]
                },
                "stats": {
                  "c42cf668-3e65-49c4-a30a-25b3a95325b1": {
                    "1591765788": [
                      0,
                      0,
                      null,
                      null,
                      null,
                      null,
                      0,
                      null,
                      null
                    ],
                  }
                }
              }
            ]]
            -- check if we have a datapoint available?
            for _, v in pairs(metrics) do -- luacheck:ignore 512 loop is executed at most once
              for _, dps in pairs(v) do
                for _, dp in ipairs(dps) do
                  if dp and dp ~= cjson.null and dp ~= 0 then
                    return true
                  end
                end
              end
              -- we only have on node
              break
            end
          end

        end, 30)
      end)
    end)

    describe("allowing vitals to be initialized/started during license preload", function()
      local db, client, reset_distribution

      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy, {"licenses"})
        reset_distribution = setup_distribution()

        assert(helpers.start_kong({
          role = "control_plane",
          database = strategy,
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
          lua_package_path = "./?.lua;./?/init.lua;./spec/fixtures/?.lua",
          db_update_frequency = 0.1,
          db_update_propagation = 0.1,
          cluster_listen = "127.0.0.1:9005",
          cluster_telemetry_listen = "127.0.0.1:9006",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          vitals = true,
          log_level = "debug",
        }))

        assert(helpers.start_kong({
          role = "data_plane",
          database = "off",
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
          lua_package_path = "./?.lua;./?/init.lua;./spec/fixtures/?.lua",
          cluster_control_plane = "127.0.0.1:9005",
          cluster_telemetry_endpoint = "127.0.0.1:9006",
          proxy_listen = "0.0.0.0:9002",
          vitals = true,
          log_level = "debug",
        }))

        client = helpers.admin_client()
      end)

      lazy_teardown(function()
        if client then
          client:close()
        end

        helpers.stop_kong("servroot2")
        helpers.stop_kong()
        reset_distribution()
      end)

      it("sends back vitals metrics to CP", function()
        local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
        local d = f:read("*a")
        f:close()

        local res = assert(client:send {
          method = "POST",
          path = "/licenses",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = { payload = d },
        })
        assert.res_status(201, res)

        helpers.wait_until(function()
          local s = pl_file.read("servroot2/logs/error.log")
          if not s:match("%[vitals%] config change event, incoming vitals: true") then
            return
          end

          if not s:match("%[vitals%] telemetry websocket is connected") then
            return
          end

          if not s:match("%[vitals%] flush %d+ bytes to CP") then
            return
          end

          return true
        end, 30)
      end)

      it("sends back vitals metrics to CP after DP restarted", function()
        db:truncate("licenses")

        local f = assert(io.open("spec-ee/fixtures/mock_license.json"))
        local d = f:read("*a")
        f:close()

        local res = assert(client:send {
          method = "POST",
          path = "/licenses",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = { payload = d },
        })
        assert.res_status(201, res)

        helpers.wait_until(function()
          local s = pl_file.read("servroot2/logs/error.log")
          if not s:match("%[vitals%] config change event, incoming vitals: true") then
            return
          end

          if not s:match("%[vitals%] telemetry websocket is connected") then
            return
          end

          if not s:match("%[vitals%] flush %d+ bytes to CP") then
            return
          end

          return true
        end,30)

        assert(helpers.restart_kong({
          role = "data_plane",
          database = "off",
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
          lua_package_path = "./?.lua;./?/init.lua;./spec/fixtures/?.lua",
          cluster_control_plane = "127.0.0.1:9005",
          cluster_telemetry_endpoint = "127.0.0.1:9006",
          proxy_listen = "0.0.0.0:9002",
          vitals = true,
          log_level = "debug",
        }))

        helpers.clean_logfile("servroot2/logs/error.log")

        helpers.wait_until(function()
          local s = pl_file.read("servroot2/logs/error.log")

          if not s:match("%[vitals%] flush %d+ bytes to CP") then
            return
          end

          return true
        end, 30)
      end)
    end)
  end)
end
