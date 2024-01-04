-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local pl_file = require "pl.file"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

-- replace distributions_constants.lua to mock a GA release distribution and
-- returns a function to restore their values on test teardown
local function setup_distribution()
  local tmp_filename = "/tmp/distributions_constants.lua"
  assert(helpers.file.copy("kong/enterprise_edition/distributions_constants.lua", tmp_filename, true))
  assert(helpers.file.copy("spec-ee/fixtures/mock_distributions_constants.lua", "kong/enterprise_edition/distributions_constants.lua", true))

  return function()
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
      local reset_license_data

      lazy_setup(function()
        reset_license_data = clear_license_env()
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
          portal_and_vitals_key = get_portal_and_vitals_key(),
          license_path = "spec-ee/fixtures/mock_license.json",
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
          portal_and_vitals_key = get_portal_and_vitals_key(),
          license_path = "spec-ee/fixtures/mock_license.json",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2")
        helpers.stop_kong()
        reset_license_data()
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

          if metrics.meta then
            local nodes = metrics.meta.nodes
            for _, node in pairs(nodes) do
              assert.is_not_nil(node.hostname)
            end
          end

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
      local reset_license_data

      lazy_setup(function()
        reset_license_data = clear_license_env()
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
          portal_and_vitals_key = get_portal_and_vitals_key(),
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
          portal_and_vitals_key = get_portal_and_vitals_key(),
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
        reset_license_data()
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

          if not s:match("sent payload to peer%(%d+ bytes%)") then
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

          if not s:match("sent payload to peer%(%d+ bytes%)") then
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
          portal_and_vitals_key = get_portal_and_vitals_key(),
          vitals = true,
          log_level = "debug",
        }))

        helpers.clean_logfile("servroot2/logs/error.log")

        helpers.wait_until(function()
          local s = pl_file.read("servroot2/logs/error.log")

          if not s:match("%[vitals%] flush %d+ bytes to CP") then
            return
          end

          if not s:match("sent payload to peer%(%d+ bytes%)") then
            return
          end

          return true
        end, 30)
      end)
    end)

    describe("de-couple the consuming and producing upon telemetry between cp/dp with queue", function()
      local db_proxy_port = "16797"
      local pg_port = "5432"
      local api_server_port, trigger_server_port  = "16000", "18000"
      local reset_license_data
      setup(function()
        reset_license_data = clear_license_env()
        local fixtures = {
          http_mock = {
            delay_trigger = [[
              server {
                error_log logs/error.log;
                listen 127.0.0.1:%s;
                location /delay {
                  content_by_lua_block {
                    local sock = ngx.socket.tcp()
                    sock:settimeout(3000)
                    local ok, err = sock:connect('127.0.0.1', '%s')
                    if ok then
                      ngx.say("ok")
                    else
                      ngx.exit(ngx.ERROR)
                    end
                  }
                }
              }
            ]],
          },

          stream_mock = {
            db_proxy = [[
              upstream backend {
                server 0.0.0.1:1234;
                balancer_by_lua_block {
                  local balancer = require "ngx.balancer"

                  local function sleep(n)
                    local t0 = os.clock()
                    while os.clock() - t0 <= n do end
                  end
                  sleep(delay or 0)
                  local ok, err = balancer.set_current_peer("127.0.0.1", %s)
                  if not ok then
                    ngx.log(ngx.ERR, "failed to set the current peer: ", err)
                    return ngx.exit(ngx.ERROR)
                  end
                }
              }

              server {
                listen %s;
                error_log logs/proxy.log debug;
                proxy_pass backend;
              }

              # trigger to increase the delay
              server {
                listen %s;
                error_log logs/proxy.log debug;
                content_by_lua_block {
                  _G.delay = 10
                  local sock = assert(ngx.req.socket())
                  local data = sock:receive()

                  if ngx.var.protocol == "TCP" then
                    ngx.say(10)
                  else
                    ngx.send(data)
                  end
                }
              }
            ]],
          },
        }

        fixtures.http_mock.delay_trigger = string.format(
          fixtures.http_mock.delay_trigger, api_server_port, trigger_server_port)

        if strategy == 'postgres' then
          fixtures.stream_mock.db_proxy = string.format(
            fixtures.stream_mock.db_proxy, pg_port, db_proxy_port, trigger_server_port)
        end

        -- proxy for db
        assert(helpers.start_kong({
            prefix = "servroot3",

            -- excludes unnecessary listening port from custom_nginx.template
            -- so that the proxy won't occupy the ports that will be used by DP
            role = "data_plane",

            database = "off",
            cluster_cert = "spec/fixtures/kong_clustering.crt",
            cluster_cert_key = "spec/fixtures/kong_clustering.key",
            lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
            proxy_listen = "0.0.0.0:16666",
            -- admin_listen = "off",
            -- cluster_listen = "off",
            -- cluster_telemetry_listen = "off",
            nginx_conf = "spec/fixtures/custom_nginx.template",

            -- this is unused, but required for the the template to include a stream {} block
            stream_listen = "0.0.0.0:5555",
          }, nil, nil, fixtures))

        helpers.setenv("KONG_TEST_PG_PORT", db_proxy_port)

        assert(helpers.start_kong({
          role = "control_plane",
          cluster_cert = "spec/fixtures/kong_clustering.crt",
          cluster_cert_key = "spec/fixtures/kong_clustering.key",
          lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
          database = strategy,
          pg_port = 16797,
          -- db_timeout should set greater than clustering_timeout(5 secs)
          pg_timeout = 10000, -- ensure pg_timeout > clustering_timeout(5 secs)
          db_update_frequency = 0.1,
          db_update_propagation = 0.1,
          cluster_listen = "127.0.0.1:9005",
          cluster_telemetry_listen = "127.0.0.1:9006",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          portal_and_vitals_key = get_portal_and_vitals_key(),
          vitals = true,
          vitals_flush_interval = 3,
          license_path = "spec-ee/fixtures/mock_license.json",
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
          vitals_flush_interval = 3,
          portal_and_vitals_key = get_portal_and_vitals_key(),
          license_path = "spec-ee/fixtures/mock_license.json",
        }))
      end)

      teardown(function()
        helpers.unsetenv("KONG_TEST_PG_PORT")
        assert(helpers.stop_kong("servroot2", true))  -- dp
        assert(helpers.stop_kong("servroot", true))   -- cp
        assert(helpers.stop_kong("servroot3", true))  -- proxy
        reset_license_data()
      end)

      it("", function()
        -- wait for vitals starts to flush
        helpers.pwait_until(function()
          assert.logfile("servroot2/logs/error.log").has.line([[\[vitals\] flush]])
          return true
        end, 3)

        -- increase the delay
        local timeout, force_port, force_ip = 3000, 16000, "127.0.0.1"
        local proxy_client = helpers.proxy_client(timeout, force_port, force_ip)
        local res = proxy_client:get("/delay")
        local body = assert.res_status(200, res)
        assert(body == "ok")

        -- wait for websocket connection to be broken if possible
        -- actually we assert it won't be broken
        ngx.sleep(20)
        assert.logfile("servroot2/logs/error.log").has_not.line(
            "error while receiving frame from peer")
      end)
    end)
  end)
end
