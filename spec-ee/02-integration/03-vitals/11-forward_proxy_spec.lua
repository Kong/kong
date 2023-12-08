-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local fixtures = {
  stream_mock = {
    forward_proxy = [[
    server {
      listen 16797;
      listen 16799 ssl;
      listen [::]:16799 ssl;

      ssl_certificate ../spec/fixtures/kong_spec.crt;
      ssl_certificate_key ../spec/fixtures/kong_spec.key;

      error_log logs/proxy.log debug;

      content_by_lua_block {
        require("spec.fixtures.forward-proxy-server").connect()
      }
    }

    server {
      listen 16796;
      listen 16798 ssl;
      listen [::]:16798 ssl;

      ssl_certificate ../spec/fixtures/kong_spec.crt;
      ssl_certificate_key ../spec/fixtures/kong_spec.key;

      error_log logs/proxy_auth.log debug;


      content_by_lua_block {
        require("spec.fixtures.forward-proxy-server").connect({
          basic_auth = ngx.encode_base64("test:konghq"),
        })
      }
    }
    ]],
  },
}


local proxy_configs = {
  ["https off auth off"] = {
    proxy_server = "http://127.0.0.1:16797",
    proxy_server_ssl_verify = "off",
  },
  ["https off auth on"] = {
    proxy_server = "http://test:konghq@127.0.0.1:16796",
    proxy_server_ssl_verify = "off",
  },
  ["https on auth off"] = {
    proxy_server = "https://127.0.0.1:16799",
    proxy_server_ssl_verify = "off",
  },
  ["https on auth on"] = {
    proxy_server = "https://test:konghq@127.0.0.1:16798",
    proxy_server_ssl_verify = "off",
  },
  ["https on auth off verify on"] = {
    proxy_server = "https://localhost:16799", -- use `localhost` to match CN of cert
    proxy_server_ssl_verify = "on",
    lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
  },
}


for _, strategy in helpers.each_strategy() do
  for proxy_desc, proxy_opts in pairs(proxy_configs) do
    describe("Hybrid vitals works throgh proxy (" .. proxy_desc .. ") with #" .. strategy .. " backend", function()
      local reset_license_data
      local db

      lazy_setup(function()
        reset_license_data = clear_license_env()

        _, db = helpers.get_db_utils(strategy, {
          "routes",
          "services",
        }) -- runs migrations

        assert(helpers.start_kong({
          role = "control_plane",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          database = strategy,
          db_update_frequency = 0.1,
          cluster_listen = "127.0.0.1:9005",
          cluster_telemetry_listen = "127.0.0.1:9006",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          vitals = true,
          portal = false,
          portal_and_vitals_key = get_portal_and_vitals_key(),
          license_path = "spec-ee/fixtures/mock_license.json",
        }))

        assert(helpers.start_kong({
          role = "data_plane",
          database = "off",
          prefix = "servroot2",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          cluster_control_plane = "127.0.0.1:9005",
          cluster_telemetry_endpoint = "127.0.0.1:9006",
          proxy_listen = "0.0.0.0:9002",
          vitals = true,
          portal = false,
          portal_and_vitals_key = get_portal_and_vitals_key(),
          license_path = "spec-ee/fixtures/mock_license.json",
          log_level = "debug",

          -- used to render the mock fixture
          nginx_conf = "spec/fixtures/custom_nginx.template",

          cluster_use_proxy = "on",
          proxy_server = proxy_opts.proxy_server,
          proxy_server_ssl_verify = proxy_opts.proxy_server_ssl_verify,
          lua_ssl_trusted_certificate = proxy_opts.lua_ssl_trusted_certificate,

          -- this is unused, but required for the the template to include a stream {} block
          stream_listen = "0.0.0.0:5555",
        }, nil, nil, fixtures))
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2")
        helpers.stop_kong()
        reset_license_data()
      end)

      before_each(function()
        db:truncate("services")
        db:truncate("routes")
      end)

      describe("sync works", function()
        it("proxy on DP follows CP config", function()
          local res, body, json_body, service_id, route_id

          local admin_client = helpers.admin_client(10000)
          finally(function()
            admin_client:close()
          end)

          res = assert(admin_client:post("/services", {
            body = { name = "mockbin-service", url = "https://127.0.0.1:15556/request", },
            headers = {["Content-Type"] = "application/json"}
          }))
          body = assert.res_status(201, res)
          json_body = cjson.decode(body)
          service_id = json_body.id

          res = assert(admin_client:post("/services/mockbin-service/routes", {
            body = { paths = { "/" }, },
            headers = {["Content-Type"] = "application/json"}
          }))
          body = assert.res_status(201, res)
          json_body = cjson.decode(body)
          route_id = json_body.id

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

          res = assert(admin_client:delete("/routes/" .. route_id, {
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)
          res = assert(admin_client:delete("/services/" .. service_id, {
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(204, res)
        end)

        it("#flaky sends back vitals metrics to DP", function()
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

          local auth_on = string.match(proxy_desc, "auth on")

          -- ensure this goes through proxy
          local path = pl_path.join("servroot2", "logs",
                                    auth_on and "proxy_auth.log" or "proxy.log")
          local contents = pl_file.read(path)
          assert.matches("CONNECT 127.0.0.1:9005", contents)
          assert.matches("CONNECT 127.0.0.1:9006", contents)

          if auth_on then
            assert.matches("accepted basic proxy%-authorization", contents)
          end

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

          end, 30)
        end)
      end)
    end)
  end
end
