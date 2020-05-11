local helpers = require "spec.helpers"
local cjson = require "cjson.safe"


for _, strategy in helpers.each_strategy() do
  describe("Hybrid vitals works with #" .. strategy .. " backend", function()

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

    describe("sync works", function()
      -- this is copied from spec/02-integration/09-hybrid-mode/01-sync_spec.lua
      it("proxy on DP follows CP config #flaky", function()
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

      it("sends back vitals metrics to DP #flaky", function()
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

        helpers.wait_until(function()
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

        end, 5)
      end)
    end)
  end)
end
