local bu = require "spec.fixtures.balancer_utils"
local cjson = require "cjson"
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"


local https_server = helpers.https_server


for _, strategy in helpers.each_strategy() do
  local bp

  local DB_UPDATE_PROPAGATION = strategy == "cassandra" and 0.1 or 0
  local DB_UPDATE_FREQUENCY   = strategy == "cassandra" and 0.1 or 0.1
  local proxy_port_1 = 9000
  local proxy_port_ssl = 9443
  local proxy_port_grpc = 9002
  local admin_port_1 = 9001
  local default_admin_listen = "127.0.0.1:".. admin_port_1 .. ",[::1]:" .. admin_port_1
  local default_proxy_listen = "127.0.0.1:".. proxy_port_1 .. ",[::1]:" .. proxy_port_1 .. ", " ..
                               "127.0.0.1:".. proxy_port_ssl .. " http2 ssl,[::1]:" .. proxy_port_ssl .. " http2 ssl, " ..
                               "127.0.0.1:".. proxy_port_grpc .. " http2,[::1]:" .. proxy_port_grpc .. " http2"

  describe("Healthcheck #" .. strategy, function()
    lazy_setup(function()
      bp = bu.get_db_utils_for_dc_and_admin_api(strategy, {
        "routes",
        "services",
        "plugins",
        "upstreams",
        "targets",
      })

      local fixtures = {
        dns_mock = helpers.dns_mock.new()
      }

      fixtures.dns_mock:SRV {
        name = "my.srv.test.com",
        target = "a.my.srv.test.com",
        port = 80,  -- port should fail to connect
      }
      fixtures.dns_mock:A {
        name = "a.my.srv.test.com",
        address = "127.0.0.1",
      }

      fixtures.dns_mock:A {
        name = "multiple-ips.test",
        address = "127.0.0.1",
      }
      fixtures.dns_mock:A {
        name = "multiple-ips.test",
        address = "127.0.0.2",
      }

      fixtures.dns_mock:SRV {
        name = "srv-changes-port.test",
        target = "a-changes-port.test",
        port = 90,  -- port should fail to connect
      }

      fixtures.dns_mock:A {
        name = "a-changes-port.test",
        address = "127.0.0.3",
      }
      fixtures.dns_mock:A {
        name = "another.multiple-ips.test",
        address = "127.0.0.1",
      }
      fixtures.dns_mock:A {
        name = "another.multiple-ips.test",
        address = "127.0.0.2",
      }

      assert(helpers.start_kong({
        database   = strategy,
        dns_resolver = "127.0.0.1",
        admin_listen = default_admin_listen,
        proxy_listen = default_proxy_listen,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_frequency = DB_UPDATE_FREQUENCY,
        db_update_propagation = DB_UPDATE_PROPAGATION,
      }, nil, nil, fixtures))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("2-level dns sets the proper health-check", function()

      -- Issue is that 2 level dns hits a mismatch between a name
      -- in the second level, and the IP address that failed.
      -- Typically an SRV pointing to an A record will result in a
      -- internal balancer structure Address that hold a name rather
      -- than an IP. So when Kong reports IP xyz failed to connect,
      -- and the healthchecker marks it as down. That IP will not be
      -- found in the balancer (since its only known by name), and hence
      -- and error is returned that the target could not be disabled.

      -- configure healthchecks
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        healthchecks = bu.healthchecks_config {
          passive = {
            unhealthy = {
              tcp_failures = 1,
            }
          }
        }
      })
      -- the following port will not be used, will be overwritten by
      -- the mocked SRV record.
      bu.add_target(bp, upstream_id, "my.srv.test.com", 80)
      local api_host = bu.add_api(bp, upstream_name)
      bu.end_testcase_setup(strategy, bp)

      -- we do not set up servers, since we want the connection to get refused
      -- Go hit the api with requests, 1x round the balancer
      local oks, fails, last_status = bu.client_requests(bu.SLOTS, api_host)
      assert.same(0, oks)
      assert.same(bu.SLOTS, fails)
      assert.same(503, last_status)

      local health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.equals("UNHEALTHY", health.data[1].health)
    end)

    it("a target that resolves to 2 IPs reports health separately", function()

      -- configure healthchecks
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        healthchecks = bu.healthchecks_config {
          passive = {
            unhealthy = {
              tcp_failures = 1,
            }
          }
        }
      })
      -- the following port will not be used, will be overwritten by
      -- the mocked SRV record.
      bu.add_target(bp, upstream_id, "multiple-ips.test", 80)
      local api_host = bu.add_api(bp, upstream_name, { connect_timeout = 100, })
      bu.end_testcase_setup(strategy, bp)

      -- we do not set up servers, since we want the connection to get refused
      -- Go hit the api with requests
      local oks, fails, last_status = bu.client_requests(bu.SLOTS, api_host)
      assert.same(0, oks)
      assert.same(bu.SLOTS, fails)
      assert.same(503, last_status)

      local health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[2].health)

      local status = bu.post_target_address_health(upstream_id, "multiple-ips.test:80", "127.0.0.2:80", "healthy")
      assert.same(204, status)

      health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("HEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("HEALTHY", health.data[1].data.addresses[2].health)

      local status = bu.post_target_address_health(upstream_id, "multiple-ips.test:80", "127.0.0.2:80", "unhealthy")
      assert.same(204, status)

      health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[2].health)

    end)

    it("a target that resolves to 2 IPs reports health separately (upstream with hostname set)", function()

      -- configure healthchecks
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        host_header = "another.multiple-ips.test",
        healthchecks = bu.healthchecks_config {
          passive = {
            unhealthy = {
              tcp_failures = 1,
            }
          }
        }
      })
      -- the following port will not be used, will be overwritten by
      -- the mocked SRV record.
      bu.add_target(bp, upstream_id, "multiple-ips.test", 80)
      local api_host = bu.add_api(bp, upstream_name, { connect_timeout = 100, })
      bu.end_testcase_setup(strategy, bp)

      -- we do not set up servers, since we want the connection to get refused
      -- Go hit the api with requests, 1x round the balancer
      local oks, fails, last_status = bu.client_requests(bu.SLOTS, api_host)
      assert.same(0, oks)
      assert.same(bu.SLOTS, fails)
      assert.same(503, last_status)

      local health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])

      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[2].health)

      local status = bu.post_target_address_health(upstream_id, "multiple-ips.test:80", "127.0.0.2:80", "healthy")
      assert.same(204, status)

      health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("HEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("HEALTHY", health.data[1].data.addresses[2].health)

      local status = bu.post_target_address_health(upstream_id, "multiple-ips.test:80", "127.0.0.2:80", "unhealthy")
      assert.same(204, status)

      health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.same("127.0.0.1", health.data[1].data.addresses[1].ip)
      assert.same("127.0.0.2", health.data[1].data.addresses[2].ip)
      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[2].health)

    end)

    it("a target that resolves to an SRV record that changes port", function()

      -- configure healthchecks
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        healthchecks = bu.healthchecks_config {
          passive = {
            unhealthy = {
              tcp_failures = 1,
            }
          }
        }
      })
      -- the following port will not be used, will be overwritten by
      -- the mocked SRV record.
      bu.add_target(bp, upstream_id, "srv-changes-port.test", 80)
      local api_host = bu.add_api(bp, upstream_name, { connect_timeout = 100, })
      bu.end_testcase_setup(strategy, bp)

      -- we do not set up servers, since we want the connection to get refused
      -- Go hit the api with requests, 1x round the balancer
      local oks, fails, last_status = bu.client_requests(bu.SLOTS, api_host)
      assert.same(0, oks)
      assert.same(bu.SLOTS, fails)
      assert.same(503, last_status)

      local health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])

      assert.same("a-changes-port.test", health.data[1].data.addresses[1].ip)
      assert.same(90, health.data[1].data.addresses[1].port)

      assert.equals("UNHEALTHY", health.data[1].health)
      assert.equals("UNHEALTHY", health.data[1].data.addresses[1].health)

      local status = bu.post_target_address_health(upstream_id, "srv-changes-port.test:80", "a-changes-port.test:90", "healthy")
      assert.same(204, status)

      health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])

      assert.same("a-changes-port.test", health.data[1].data.addresses[1].ip)
      assert.same(90, health.data[1].data.addresses[1].port)

      assert.equals("HEALTHY", health.data[1].health)
      assert.equals("HEALTHY", health.data[1].data.addresses[1].health)
    end)

    it("a target that has healthchecks disabled", function()
      -- configure healthchecks
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        healthchecks = bu.healthchecks_config {
          passive = {
            unhealthy = {
              http_failures = 0,
              tcp_failures = 0,
              timeouts = 0,
            },
          },
          active = {
            healthy = {
              interval = 0,
            },
            unhealthy = {
              interval = 0,
            },
          },
        }
      })
      bu.add_target(bp, upstream_id, "multiple-ips.test", 80)
      bu.add_api(bp, upstream_name)
      bu.end_testcase_setup(strategy, bp)
      local health = bu.get_upstream_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is.table(health.data[1])
      assert.equals("HEALTHCHECKS_OFF", health.data[1].health)
      assert.equals("HEALTHCHECKS_OFF", health.data[1].data.addresses[1].health)
    end)

  end)

  describe("mTLS #" .. strategy, function()

    local get_name
    do
      local n = 0
      get_name = function()
        n = n + 1
        return string.format("name%04d.test", n)
      end
    end


    lazy_setup(function()
      bp = bu.get_db_utils_for_dc_and_admin_api(strategy, {
        "services",
        "routes",
        "upstreams",
        "targets",
      })

      local fixtures = {
        dns_mock = helpers.dns_mock.new()
      }

      fixtures.dns_mock:A {
        name = "notlocalhost.test",
        address = "127.0.0.1",
      }

      assert(helpers.start_kong({
        database   = strategy,
        admin_listen = default_admin_listen,
        proxy_listen = default_proxy_listen,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        client_ssl = true,
        client_ssl_cert = "spec/fixtures/kong_spec.crt",
        client_ssl_cert_key = "spec/fixtures/kong_spec.key",
        db_update_frequency = 0.1,
        stream_listen = "off",
        plugins = "bundled,fail-once-auth",
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("create active health checks -- global certificate", function()
      -- configure healthchecks
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        healthchecks = bu.healthchecks_config {
          active = {
            type = "https",
            http_path = "/status",
            healthy = {
              interval = bu.HEALTHCHECK_INTERVAL,
              successes = 1,
            },
            unhealthy = {
              interval = bu.HEALTHCHECK_INTERVAL,
              http_failures = 1,
            },
          }
        }
      })
      bu.add_target(bp, upstream_id, "notlocalhost.test", 15555)
      bu.end_testcase_setup(strategy, bp)

      local health = bu.get_balancer_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      bu.poll_wait_health(upstream_id, "notlocalhost.test", "15555", "UNHEALTHY")
    end)

    it("#db create active health checks -- upstream certificate", function()
      local ssl_fixtures = require "spec.fixtures.ssl"
      local client = assert(helpers.admin_client())
      local res = client:post("/certificates", {
        body    = {
          cert = ssl_fixtures.cert,
          key = ssl_fixtures.key,
          snis  = { get_name(), get_name() },
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      local body = assert.res_status(201, res)
      local certificate = cjson.decode(body)

      -- configure healthchecks
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        healthchecks = bu.healthchecks_config {
          active = {
            type = "https",
            http_path = "/status",
            healthy = {
              interval = bu.HEALTHCHECK_INTERVAL,
              successes = 1,
            },
            unhealthy = {
              interval = bu.HEALTHCHECK_INTERVAL,
              http_failures = 1,
            },
          }
        },
        client_certificate = certificate,
      })
      bu.add_target(bp, upstream_id, "notlocalhost.test", 15555)
      bu.end_testcase_setup(strategy, bp)

      local health = bu.get_balancer_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      bu.poll_wait_health(upstream_id, "notlocalhost.test", "15555", "UNHEALTHY")
    end)
  end)

  describe("Ring-balancer #" .. strategy, function()

    lazy_setup(function()
      bp = bu.get_db_utils_for_dc_and_admin_api(strategy, {
        "services",
        "routes",
        "upstreams",
        "targets",
      })

      assert(helpers.start_kong({
        database   = strategy,
        dns_resolver = "127.0.0.1",
        admin_listen = default_admin_listen,
        proxy_listen = default_proxy_listen,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
        stream_listen = "off",
        db_update_frequency = DB_UPDATE_FREQUENCY,
        db_update_propagation = DB_UPDATE_PROPAGATION,
        plugins = "bundled,fail-once-auth",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("#healthchecks (#cluster #db)", function()

      -- second node ports are Kong test ports + 10
      local proxy_port_2 = 9010
      local admin_port_2 = 9011

      lazy_setup(function()
        -- start a second Kong instance
        helpers.start_kong({
          database   = strategy,
          dns_resolver = "127.0.0.1",
          admin_listen = "127.0.0.1:".. admin_port_2 .. ",[::1]:" .. admin_port_2,
          proxy_listen = "127.0.0.1:".. proxy_port_2 .. ",[::1]:" .. proxy_port_2,
          stream_listen = "off",
          prefix = "servroot2",
          log_level = "debug",
          db_update_frequency = DB_UPDATE_FREQUENCY,
          db_update_propagation = DB_UPDATE_PROPAGATION,
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong("servroot2")
      end)

      for mode, localhost in pairs(bu.localhosts) do

        describe("#" .. mode, function()

          -- FIXME for some reason this test fails only on CI
          it("#flaky does not perform health checks when disabled (#3304)", function()

            bu.begin_testcase_setup(strategy, bp)
            local old_rv = bu.get_router_version(admin_port_2)
            local upstream_name, upstream_id = bu.add_upstream(bp)
            local port = bu.add_target(bp, upstream_id, localhost)
            local api_host = bu.add_api(bp, upstream_name)
            bu.wait_for_router_update(bp, old_rv, localhost, proxy_port_1, admin_port_1)
            old_rv = bu.get_router_version(admin_port_1)
            bu.wait_for_router_update(bp, old_rv, localhost, proxy_port_2, admin_port_2)
            bu.end_testcase_setup(strategy, bp)

            local server = https_server.new(port, upstream_name)
            server:start()

            -- server responds, then fails, then responds again
            local seq = {
              { healthy = true, port = proxy_port_2, oks = 10, fails = 0, last_status = 200 },
              { healthy = true, port = proxy_port_1, oks = 10, fails = 0, last_status = 200 },
              { healthy = false, port = proxy_port_2, oks = 0, fails = 10, last_status = 500 },
              { healthy = false, port = proxy_port_1, oks = 0, fails = 10, last_status = 500 },
              { healthy = true, port = proxy_port_2, oks = 10, fails = 0, last_status = 200 },
              { healthy = true, port = proxy_port_1, oks = 10, fails = 0, last_status = 200 },
            }
            for i, test in ipairs(seq) do
              if test.healthy then
                bu.direct_request(localhost, port, "/healthy")
              else
                bu.direct_request(localhost, port, "/unhealthy")
              end

              if mode == "ipv6" then
                bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port, "HEALTHCHECKS_OFF")
              else
                bu.poll_wait_health(upstream_id, localhost, port, "HEALTHCHECKS_OFF")
              end

              local oks, fails, last_status = bu.client_requests(10, api_host, localhost, test.port)
              assert.same(test.oks, oks, localhost .. " iteration " .. tostring(i))
              assert.same(test.fails, fails, localhost .. " iteration " .. tostring(i))
              assert.same(test.last_status, last_status, localhost .. " iteration " .. tostring(i))
            end

            -- collect server results
            local count = server:shutdown()
            assert.same(40, count.ok)
            assert.same(20, count.fail)

          end)

          it("#flaky propagates posted health info", function()

            bu.begin_testcase_setup(strategy, bp)
            local old_rv = bu.get_router_version(admin_port_2)
            local _, upstream_id = bu.add_upstream(bp, {
              healthchecks = bu.healthchecks_config({})
            })
            local port = bu.add_target(bp, upstream_id, localhost)
            bu.wait_for_router_update(bp, old_rv, localhost, proxy_port_2, admin_port_2)
            bu.end_testcase_setup(strategy, bp)

            local health1 = bu.get_upstream_health(upstream_id, admin_port_1)
            local health2 = bu.get_upstream_health(upstream_id, admin_port_2)

            assert.same("HEALTHY", health1.data[1].health)
            assert.same("HEALTHY", health2.data[1].health)

            if mode == "ipv6" then
              -- TODO /upstreams does not understand shortened IPv6 addresses
              bu.post_target_endpoint(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port, "unhealthy")
              bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port, "UNHEALTHY", admin_port_1)
              bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port, "UNHEALTHY", admin_port_2)
            else
              bu.post_target_endpoint(upstream_id, localhost, port, "unhealthy")
              bu.poll_wait_health(upstream_id, localhost, port, "UNHEALTHY", admin_port_1)
              bu.poll_wait_health(upstream_id, localhost, port, "UNHEALTHY", admin_port_2)
            end

          end)

        end)

        describe("#" .. mode, function()
          for _, consistency in ipairs(bu.consistencies) do
            describe("Upstream entities #" .. consistency, function()

              -- Regression test for a missing invalidation in 0.12rc1
              it("created via the API are functional", function()
                bu.begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = bu.add_upstream(bp)
                local target_port = bu.add_target(bp, upstream_id, localhost)
                local api_host = bu.add_api(bp, upstream_name)
                bu.end_testcase_setup(strategy, bp, consistency)

                local server = https_server.new(target_port, localhost)
                server:start()

                local oks, fails, last_status = bu.client_requests(1, api_host)
                assert.same(200, last_status)
                assert.same(1, oks)
                assert.same(0, fails)

                local count = server:shutdown()
                assert.same(1, count.ok)
                assert.same(0, count.fail)
              end)

              it("created via the API are functional #grpc", function()
                bu.begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = bu.add_upstream(bp)
                bu.add_target(bp, upstream_id, localhost, 15002)
                local api_host = bu.add_api(bp, upstream_name, {
                  service_protocol = "grpc",
                  route_protocol = "grpc",
                })
                bu.end_testcase_setup(strategy, bp, consistency)

                local grpc_client = helpers.proxy_client_grpc()
                local ok, resp = grpc_client({
                  service = "hello.HelloService.SayHello",
                  opts = {
                    ["-authority"] = api_host,
                  }
                })
                assert.Truthy(ok)
                assert.Truthy(resp)
              end)

              it("properly set the host header", function()
                bu.begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = bu.add_upstream(bp, { host_header = "localhost" })
                local target_port = bu.add_target(bp, upstream_id, localhost)
                local api_host = bu.add_api(bp, upstream_name)
                bu.end_testcase_setup(strategy, bp, consistency)

                local server = https_server.new(target_port, "localhost",  "http", true)
                server:start()

                local oks, fails, last_status = bu.client_requests(5, api_host)
                assert.same(200, last_status)
                assert.same(5, oks)
                assert.same(0, fails)

                local count = server:shutdown()
                assert.same(5, count.ok)
                assert.same(0, count.fail)
              end)

              it("fail with wrong host header", function()
                bu.begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = bu.add_upstream(bp, { host_header = "localhost" })
                local target_port = bu.add_target(bp, upstream_id, "localhost")
                local api_host = bu.add_api(bp, upstream_name, { connect_timeout = 100, })
                bu.end_testcase_setup(strategy, bp, consistency)

                local server = https_server.new(target_port, "127.0.0.1", "http", true)
                server:start()
                local oks, fails, last_status = bu.client_requests(5, api_host)
                assert.same(400, last_status)
                assert.same(0, oks)
                assert.same(5, fails)

                -- oks and fails must be 0 as localhost should not receive any request
                local count = server:shutdown()
                assert.same(0, count.ok)
                assert.same(0, count.fail)
              end)

              -- #db == disabled for database=off, because it tests
              -- for a PATCH operation
              it("#db can have their config partially updated", function()
                bu.begin_testcase_setup(strategy, bp)
                local _, upstream_id = bu.add_upstream(bp)
                bu.end_testcase_setup(strategy, bp, consistency)

                bu.begin_testcase_setup_update(strategy, bp)
                bu.patch_upstream(upstream_id, {
                  healthchecks = {
                    active = {
                      http_path = "/status",
                      healthy = {
                        interval = 0,
                        successes = 1,
                      },
                      unhealthy = {
                        interval = 0,
                        http_failures = 1,
                      },
                    }
                  }
                })
                bu.end_testcase_setup(strategy, bp, consistency)

                local updated = {
                  active = {
                    type = "http",
                    concurrency = 10,
                    healthy = {
                      http_statuses = { 200, 302 },
                      interval = 0,
                      successes = 1
                    },
                    http_path = "/status",
                    https_sni = cjson.null,
                    https_verify_certificate = true,
                    timeout = 1,
                    unhealthy = {
                      http_failures = 1,
                      http_statuses = { 429, 404, 500, 501, 502, 503, 504, 505 },
                      interval = 0,
                      tcp_failures = 0,
                      timeouts = 0
                    }
                  },
                  passive = {
                    type = "http",
                    healthy = {
                      http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226,
                                        300, 301, 302, 303, 304, 305, 306, 307, 308 },
                      successes = 0
                    },
                    unhealthy = {
                      http_failures = 0,
                      http_statuses = { 429, 500, 503 },
                      tcp_failures = 0,
                      timeouts = 0
                    }
                  },
                  threshold = 0
                }

                local upstream_data = bu.get_upstream(upstream_id)
                assert.same(updated, upstream_data.healthchecks)
              end)

              -- #db == disabled for database=off, because it tests
              -- for a PATCH operation.
              -- TODO produce an equivalent test when upstreams are preserved
              -- (not rebuilt) across declarative config updates.
              it("#db can be renamed without producing stale cache", function()
                -- create two upstreams, each with a target pointing to a server
                bu.begin_testcase_setup(strategy, bp)
                local upstreams = {}
                for i = 1, 2 do
                  upstreams[i] = {}
                  upstreams[i].name = bu.add_upstream(bp, {
                    healthchecks = bu.healthchecks_config {}
                  })
                  upstreams[i].port = bu.add_target(bp, upstreams[i].name, localhost)
                  upstreams[i].api_host = bu.add_api(bp, upstreams[i].name)
                end
                bu.end_testcase_setup(strategy, bp, consistency)

                -- start two servers
                local server1 = https_server.new(upstreams[1].port, localhost)
                local server2 = https_server.new(upstreams[2].port, localhost)
                server1:start()
                server2:start()

                -- rename upstream 2
                local new_name = upstreams[2].name .. "_new"
                bu.patch_upstream(upstreams[2].name, {
                  name = new_name,
                })

                -- rename upstream 1 to upstream 2's original name
                bu.patch_upstream(upstreams[1].name, {
                  name = upstreams[2].name,
                })

                if consistency == "eventual" then
                  ngx.sleep(bu.CONSISTENCY_FREQ) -- wait for proxy state consistency timer
                end

                -- hit a request through upstream 1 using the new name
                local oks, fails, last_status = bu.client_requests(1, upstreams[2].api_host)
                assert.same(200, last_status)
                assert.same(1, oks)
                assert.same(0, fails)

                -- rename upstream 2
                bu.patch_upstream(new_name, {
                  name = upstreams[1].name,
                })

                if consistency == "eventual" then
                  ngx.sleep(bu.CONSISTENCY_FREQ) -- wait for proxy state consistency timer
                end

                -- a single request to upstream 2 just to make server 2 shutdown
                bu.client_requests(1, upstreams[1].api_host)

                -- collect results
                local count1 = server1:shutdown()
                local count2 = server2:shutdown()
                assert.same({1, 0}, { count1.ok, count1.fail })
                assert.same({1, 0}, { count2.ok, count2.fail })
              end)

              -- #db == disabled for database=off, because it tests
              -- for a PATCH operation.
              -- TODO produce an equivalent test when upstreams are preserved
              -- (not rebuilt) across declarative config updates.
              -- FIXME when using eventual consistency sometimes it takes a long
              -- time to stop the original health checker, it may be a bug or not.
              it("#db do not leave a stale healthchecker when renamed", function()
                if consistency ~= "eventual" then
                  bu.begin_testcase_setup(strategy, bp)

                  -- create an upstream
                  local upstream_name, upstream_id = bu.add_upstream(bp, {
                    healthchecks = bu.healthchecks_config {
                      active = {
                        http_path = "/status",
                        healthy = {
                          interval = bu.HEALTHCHECK_INTERVAL,
                          successes = 1,
                        },
                        unhealthy = {
                          interval = bu.HEALTHCHECK_INTERVAL,
                          http_failures = 1,
                        },
                      }
                    }
                  })
                  local port = bu.add_target(bp, upstream_id, localhost)
                  local _, service_id = bu.add_api(bp, upstream_name)

                  bu.end_testcase_setup(strategy, bp, consistency)

                  -- rename upstream
                  local new_name = upstream_id .. "_new"
                  bu.patch_upstream(upstream_id, {
                    name = new_name
                  })

                  -- reconfigure healthchecks
                  bu.patch_upstream(new_name, {
                    healthchecks = {
                      active = {
                        http_path = "/status",
                        healthy = {
                          interval = 0,
                          successes = 1,
                        },
                        unhealthy = {
                          interval = 0,
                          http_failures = 1,
                        },
                      }
                    }
                  })

                  -- wait for old healthchecks to stop
                  ngx.sleep(0.5)

                  -- start server
                  local server1 = https_server.new(port, localhost)
                  server1:start()

                  -- give time for healthchecker to (not!) run
                  ngx.sleep(bu.HEALTHCHECK_INTERVAL * 3)

                  bu.begin_testcase_setup_update(strategy, bp)
                  bu.patch_api(bp, service_id, "http://" .. new_name)
                  bu.end_testcase_setup(strategy, bp, consistency)

                  -- collect results
                  local count = server1:shutdown()
                  assert.same({0, 0}, { count.ok, count.fail })
                  assert.truthy(count.status_total < 2)
                end
              end)

            end)
          end

          describe("#healthchecks", function()

            local stream_it = (mode == "ipv6" or strategy == "off") and pending or it

            it("do not count Kong-generated errors as failures", function()

              bu.begin_testcase_setup(strategy, bp)

              -- configure healthchecks with a 1-error threshold
              local upstream_name, upstream_id = bu.add_upstream(bp, {
                healthchecks = bu.healthchecks_config {
                  passive = {
                    healthy = {
                      successes = 1,
                    },
                    unhealthy = {
                      http_statuses = { 401, 500 },
                      http_failures = 1,
                      tcp_failures = 1,
                      timeouts = 1,
                    },
                  }
                }
              })
              local port1 = bu.add_target(bp, upstream_id, localhost)
              local port2 = bu.add_target(bp, upstream_id, localhost)
              local api_host, service_id = bu.add_api(bp, upstream_name, { connect_timeout = 50, })

              -- add a plugin
              local plugin_id = utils.uuid()
              bp.plugins:insert({
                id = plugin_id,
                service = { id = service_id },
                name = "fail-once-auth",
              })

              bu.end_testcase_setup(strategy, bp)

              -- run request: fails with 401, but doesn't hit the 1-error threshold
              local oks, fails, last_status = bu.client_requests(1, api_host)
              assert.same(0, oks)
              assert.same(1, fails)
              assert.same(401, last_status)

              -- start servers, they are unaffected by the failure above
              local server1 = https_server.new(port1, localhost)
              local server2 = https_server.new(port2, localhost)
              server1:start()
              server2:start()

              oks, fails = bu.client_requests(bu.SLOTS * 2, api_host)
              assert.same(bu.SLOTS * 2, oks)
              assert.same(0, fails)

              -- collect server results
              local count1 = server1:shutdown()
              local count2 = server2:shutdown()

              -- both servers were fully operational
              assert.same(bu.SLOTS, count1.ok)
              assert.same(bu.SLOTS, count2.ok)
              assert.same(0, count1.fail)
              assert.same(0, count2.fail)

            end)

            -- FIXME it seems this tests are actually failing
            it("#flaky perform passive health checks", function()

              for nfails = 1, 3 do

                bu.begin_testcase_setup(strategy, bp)
                -- configure healthchecks
                local upstream_name, upstream_id = bu.add_upstream(bp, {
                  healthchecks = bu.healthchecks_config {
                    passive = {
                      unhealthy = {
                        http_failures = nfails,
                      }
                    }
                  }
                })
                local port1 = bu.add_target(bp, upstream_id, localhost)
                local port2 = bu.add_target(bp, upstream_id, localhost)
                local api_host = bu.add_api(bp, upstream_name)
                bu.end_testcase_setup(strategy, bp)

                local requests = bu.SLOTS * 2 -- go round the balancer twice

                -- setup target servers:
                -- server2 will only respond for part of the test,
                -- then server1 will take over.
                local server2_oks = math.floor(requests / 4)
                local server1 = https_server.new(port1, localhost)
                local server2 = https_server.new(port2, localhost)
                server1:start()
                server2:start()

                -- Go hit them with our test requests
                local client_oks1, client_fails1 = bu.client_requests(bu.SLOTS, api_host)
                bu.direct_request(localhost, port2, "/unhealthy")
                local client_oks2, client_fails2 = bu.client_requests(bu.SLOTS, api_host)

                local client_oks = client_oks1 + client_oks2
                local client_fails = client_fails1 + client_fails2

                -- collect server results; hitcount
                local count1 = server1:shutdown()
                local count2 = server2:shutdown()

                -- verify
                assert.are.equal(requests - server2_oks - nfails, count1.ok)
                assert.are.equal(server2_oks, count2.ok)
                assert.are.equal(0, count1.fail)
                assert.are.equal(nfails, count2.fail)

                assert.are.equal(requests - nfails, client_oks)
                assert.are.equal(nfails, client_fails)
              end
            end)

            it("threshold for health checks", function()
              local fixtures = {
                dns_mock = helpers.dns_mock.new()
              }
              fixtures.dns_mock:A {
                name = "health-threshold.test",
                address = "127.0.0.1",
              }
              fixtures.dns_mock:A {
                name = "health-threshold.test",
                address = "127.0.0.2",
              }
              fixtures.dns_mock:A {
                name = "health-threshold.test",
                address = "127.0.0.3",
              }
              fixtures.dns_mock:A {
                name = "health-threshold.test",
                address = "127.0.0.4",
              }

              -- restart Kong
              bu.begin_testcase_setup_update(strategy, bp)
              helpers.restart_kong({
                database = strategy,
                admin_listen = default_admin_listen,
                proxy_listen = default_proxy_listen,
                nginx_conf = "spec/fixtures/custom_nginx.template",
                lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
                db_update_frequency = 0.1,
                stream_listen = "off",
                plugins = "bundled,fail-once-auth",
              }, nil, fixtures)
              bu.end_testcase_setup(strategy, bp)

              local health_threshold = { 0, 25, 75, 99, 100 }
              for i = 1, 5 do
                -- configure healthchecks
                bu.begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = bu.add_upstream(bp, {
                  healthchecks = bu.healthchecks_config {
                    passive = {
                      unhealthy = {
                        tcp_failures = 1,
                      }
                    },
                    threshold = health_threshold[i],
                  }
                })

                bu.add_target(bp, upstream_id, "health-threshold.test", 80, { weight = 25 })
                bu.end_testcase_setup(strategy, bp)

                -- 100% healthy
                bu.post_target_address_health(upstream_id, "health-threshold.test:80", "127.0.0.1:80", "healthy")
                bu.post_target_address_health(upstream_id, "health-threshold.test:80", "127.0.0.2:80", "healthy")
                bu.post_target_address_health(upstream_id, "health-threshold.test:80", "127.0.0.3:80", "healthy")
                bu.post_target_address_health(upstream_id, "health-threshold.test:80", "127.0.0.4:80", "healthy")

                local health = bu.get_balancer_health(upstream_name)
                assert.is.table(health)
                assert.is.table(health.data)

                assert.same({
                  available = 100,
                  unavailable = 0,
                  total = 100,
                }, health.data.details.weight)

                if health_threshold[i] < 100 then
                  assert.equals("HEALTHY", health.data.health)
                else
                  assert.equals("UNHEALTHY", health.data.health)
                end

                -- 75% healthy
                bu.post_target_address_health(upstream_id, "health-threshold.test:80", "127.0.0.1:80", "unhealthy")
                health = bu.get_balancer_health(upstream_name)

                assert.same({
                  available = 75,
                  unavailable = 25,
                  total = 100,
                }, health.data.details.weight)

                if health_threshold[i] < 75 then
                  assert.equals("HEALTHY", health.data.health)
                else
                  assert.equals("UNHEALTHY", health.data.health)
                end

                -- 50% healthy
                bu.post_target_address_health(upstream_id, "health-threshold.test:80", "127.0.0.2:80", "unhealthy")
                health = bu.get_balancer_health(upstream_name)

                assert.same({
                  available = 50,
                  unavailable = 50,
                  total = 100,
                }, health.data.details.weight)

                if health_threshold[i] < 50 then
                  assert.equals("HEALTHY", health.data.health)
                else
                  assert.equals("UNHEALTHY", health.data.health)
                end

                -- 25% healthy
                bu.post_target_address_health(upstream_id, "health-threshold.test:80", "127.0.0.3:80", "unhealthy")
                health = bu.get_balancer_health(upstream_name)

                assert.same({
                  available = 25,
                  unavailable = 75,
                  total = 100,
                }, health.data.details.weight)

                if health_threshold[i] < 25 then
                  assert.equals("HEALTHY", health.data.health)
                else
                  assert.equals("UNHEALTHY", health.data.health)
                end

                -- 0% healthy
                bu.post_target_address_health(upstream_id, "health-threshold.test:80", "127.0.0.4:80", "unhealthy")
                health = bu.get_balancer_health(upstream_name)

                assert.same({
                  available = 0,
                  unavailable = 100,
                  total = 100,
                }, health.data.details.weight)

                assert.equals("UNHEALTHY", health.data.health)

              end
            end)

            stream_it("#stream and http modules do not duplicate active health checks", function()

              local port1 = bu.gen_port()

              local server1 = https_server.new(port1, localhost)
              server1:start()

              -- configure healthchecks
              bu.begin_testcase_setup(strategy, bp)
              local _, upstream_id = bu.add_upstream(bp, {
                healthchecks = bu.healthchecks_config {
                  active = {
                    http_path = "/status",
                    healthy = {
                      -- using this interval to get the same results when using
                      -- worker_consistency "strict" or "eventual"
                      interval = bu.CONSISTENCY_FREQ,
                      successes = 1,
                    },
                    unhealthy = {
                      interval = bu.CONSISTENCY_FREQ,
                      http_failures = 1,
                    },
                  }
                }
              })
              bu.add_target(bp, upstream_id, localhost, port1)
              bu.end_testcase_setup(strategy, bp)

              -- collect server results; hitcount
              local count1 = server1:shutdown()
              assert(count1.status_total < 3)
            end)

            it("#flaky perform active health checks -- up then down", function()

              for nfails = 1, 3 do

                local requests = bu.SLOTS * 2 -- go round the balancer twice
                local port1 = bu.gen_port()
                local port2 = bu.gen_port()

                -- setup target servers:
                -- server2 will only respond for part of the test,
                -- then server1 will take over.
                local server2_oks = math.floor(requests / 4)
                local server1 = https_server.new(port1, localhost)
                local server2 = https_server.new(port2, localhost)
                server1:start()
                server2:start()

                -- configure healthchecks
                bu.begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = bu.add_upstream(bp, {
                  healthchecks = bu.healthchecks_config {
                    active = {
                      http_path = "/status",
                      healthy = {
                        interval = bu.HEALTHCHECK_INTERVAL,
                        successes = 1,
                      },
                      unhealthy = {
                        interval = bu.HEALTHCHECK_INTERVAL,
                        http_failures = nfails,
                      },
                    }
                  }
                })
                bu.add_target(bp, upstream_id, localhost, port1)
                bu.add_target(bp, upstream_id, localhost, port2)
                local api_host = bu.add_api(bp, upstream_name, { connect_timeout = 50, })
                bu.end_testcase_setup(strategy, bp)

                -- Phase 1: server1 and server2 take requests
                local client_oks, client_fails = bu.client_requests(server2_oks * 2, api_host)

                -- Phase 2: server2 goes unhealthy
                bu.direct_request(localhost, port2, "/unhealthy")

                -- Give time for healthchecker to detect
                if mode == "ipv6" then
                  bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "UNHEALTHY")
                else
                  bu.poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")
                end

                -- Phase 3: server1 takes all requests
                do
                  local p3oks, p3fails = bu.client_requests(requests - (server2_oks * 2), api_host)
                  client_oks = client_oks + p3oks
                  client_fails = client_fails + p3fails
                end

                -- collect server results; hitcount
                local count1 = server1:shutdown()
                local count2 = server2:shutdown()

                -- verify
                assert.are.equal(requests - server2_oks, count1.ok)
                assert.are.equal(server2_oks, count2.ok)
                assert.are.equal(0, count1.fail)
                assert.are.equal(0, count2.fail)

                assert.are.equal(requests, client_oks)
                assert.are.equal(0, client_fails)
              end
            end)

            it("perform active health checks with upstream hostname #flaky", function()

              for nfails = 1, 3 do

                local requests = bu.SLOTS * 2 -- go round the balancer twice
                local port1 = bu.gen_port()
                local port2 = bu.gen_port()

                -- setup target servers:
                -- server2 will only respond for part of the test,
                -- then server1 will take over.
                local server2_oks = math.floor(requests / 4)
                local server1 = https_server.new(port1, "localhost", "http", true)
                local server2 = https_server.new(port2, "localhost", "http", true)
                server1:start()
                server2:start()

                -- configure healthchecks
                bu.begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = bu.add_upstream(bp, {
                  host_header = "localhost",
                  healthchecks = bu.healthchecks_config {
                    active = {
                      http_path = "/status",
                      healthy = {
                        interval = bu.HEALTHCHECK_INTERVAL,
                        successes = 1,
                      },
                      unhealthy = {
                        interval = bu.HEALTHCHECK_INTERVAL,
                        http_failures = nfails,
                      },
                    }
                  }
                })
                bu.add_target(bp, upstream_id, localhost, port1)
                bu.add_target(bp, upstream_id, localhost, port2)
                local api_host = bu.add_api(bp, upstream_name)
                bu.end_testcase_setup(strategy, bp)

                -- Phase 1: server1 and server2 take requests
                local client_oks, client_fails = bu.client_requests(server2_oks * 2, api_host)

                -- Phase 2: server2 goes unhealthy
                bu.direct_request("localhost", port2, "/unhealthy")

                -- Give time for healthchecker to detect
                bu.poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")

                -- Phase 3: server1 takes all requests
                do
                  local p3oks, p3fails = bu.client_requests(requests - (server2_oks * 2), api_host)
                  client_oks = client_oks + p3oks
                  client_fails = client_fails + p3fails
                end

                -- collect server results; hitcount
                local count1 = server1:shutdown()
                local count2 = server2:shutdown()

                -- verify
                assert.are.equal(requests - server2_oks, count1.ok)
                assert.are.equal(server2_oks, count2.ok)
                assert.are.equal(0, count1.fail)
                assert.are.equal(0, count2.fail)

                assert.are.equal(requests, client_oks)
                assert.are.equal(0, client_fails)
              end
            end)

            for _, protocol in ipairs({"http", "https"}) do
              -- TODO this test is marked as flaky because add_upstream fails
              -- sometimes with "connection reset by peer" error, seems
              -- completely unrelated to the functionality being tested.
              it("perform active health checks -- automatic recovery #flaky #" .. protocol, function()
                for _, nchecks in ipairs({1,3}) do

                  local port1 = bu.gen_port()
                  local port2 = bu.gen_port()

                  -- setup target servers:
                  -- server2 will only respond for part of the test,
                  -- then server1 will take over.
                  local server1 = https_server.new(port1, localhost, protocol, false)
                  local server2 = https_server.new(port2, localhost, protocol, false)
                  server1:start()
                  server2:start()

                  -- configure healthchecks
                  bu.begin_testcase_setup(strategy, bp)
                  local upstream_name, upstream_id = bu.add_upstream(bp, {
                    healthchecks = bu.healthchecks_config {
                      active = {
                        type = protocol,
                        http_path = "/status",
                        https_verify_certificate = false,
                        healthy = {
                          interval = bu.HEALTHCHECK_INTERVAL,
                          successes = nchecks,
                        },
                        unhealthy = {
                          interval = bu.HEALTHCHECK_INTERVAL,
                          http_failures = nchecks,
                        },
                      }
                    }
                  })
                  bu.add_target(bp, upstream_id, localhost, port1)
                  bu.add_target(bp, upstream_id, localhost, port2)
                  local api_host = bu.add_api(bp, upstream_name, {
                    service_protocol = protocol
                  })

                  bu.end_testcase_setup(strategy, bp)

                  -- ensure it's healthy at the beginning of the test
                  bu.direct_request(localhost, port1, "/healthy", protocol)
                  bu.direct_request(localhost, port2, "/healthy", protocol)
                  if mode == "ipv6" then
                    bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port1, "HEALTHY")
                    bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "HEALTHY")
                  else
                    bu.poll_wait_health(upstream_id, localhost, port1, "HEALTHY")
                    bu.poll_wait_health(upstream_id, localhost, port2, "HEALTHY")
                  end

                  -- 1) server1 and server2 take requests
                  local oks, fails = bu.client_requests(bu.SLOTS, api_host)

                  -- server2 goes unhealthy
                  bu.direct_request(localhost, port2, "/unhealthy", protocol)
                  -- Wait until healthchecker detects
                  if mode == "ipv6" then
                    bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "UNHEALTHY")
                  else
                    bu.poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")
                  end

                  -- 2) server1 takes all requests
                  do
                    local o, f = bu.client_requests(bu.SLOTS, api_host)
                    oks = oks + o
                    fails = fails + f
                  end

                  -- server2 goes healthy again
                  bu.direct_request(localhost, port2, "/healthy", protocol)
                  -- Give time for healthchecker to detect
                  if mode == "ipv6" then
                    bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "HEALTHY")
                  else
                    bu.poll_wait_health(upstream_id, localhost, port2, "HEALTHY")
                  end

                  -- 3) server1 and server2 take requests again
                  do
                    local o, f = bu.client_requests(bu.SLOTS, api_host)
                    oks = oks + o
                    fails = fails + f
                  end

                  -- collect server results; hitcount
                  local count1 = server1:shutdown()
                  local count2 = server2:shutdown()

                  -- verify
                  assert.are.equal(bu.SLOTS * 2, count1.ok)
                  assert.are.equal(bu.SLOTS, count2.ok)
                  assert.are.equal(0, count1.fail)
                  assert.are.equal(0, count2.fail)

                  assert.are.equal(bu.SLOTS * 3, oks)
                  assert.are.equal(0, fails)
                end
              end)

              -- FIXME this test is flaky in CI only
              it("#flaky perform active health checks on a target that resolves to multiple addresses -- automatic recovery #" .. protocol, function()
                local hosts = {}

                local fixtures = {
                  dns_mock = helpers.dns_mock.new()
                }

                for i = 1, 3 do
                  hosts[i] = {
                    hostname = bu.gen_multi_host(),
                    port1 = bu.gen_port(),
                    port2 = bu.gen_port(),
                  }
                  fixtures.dns_mock:SRV {
                    name = hosts[i].hostname,
                    target = localhost,
                    port = hosts[i].port1,
                  }
                  fixtures.dns_mock:SRV {
                    name = hosts[i].hostname,
                    target = localhost,
                    port = hosts[i].port2,
                  }
                end

                -- restart Kong
                bu.begin_testcase_setup_update(strategy, bp)
                helpers.restart_kong({
                  database = strategy,
                  admin_listen = default_admin_listen,
                  proxy_listen = default_proxy_listen,
                  nginx_conf = "spec/fixtures/custom_nginx.template",
                  lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
                  db_update_frequency = 0.1,
                  stream_listen = "off",
                  plugins = "bundled,fail-once-auth",
                }, nil, fixtures)
                bu.end_testcase_setup(strategy, bp)

                for _, nchecks in ipairs({1,3}) do

                  local port1 = hosts[nchecks].port1
                  local port2 = hosts[nchecks].port2
                  local hostname = hosts[nchecks].hostname

                  -- setup target servers:
                  -- server2 will only respond for part of the test,
                  -- then server1 will take over.
                  local server1 = https_server.new(port1, hostname, protocol)
                  local server2 = https_server.new(port2, hostname, protocol)
                  server1:start()
                  server2:start()

                  -- configure healthchecks
                  bu.begin_testcase_setup(strategy, bp)
                  local upstream_name, upstream_id = bu.add_upstream(bp, {
                    healthchecks = bu.healthchecks_config {
                      active = {
                        type = protocol,
                        http_path = "/status",
                        https_verify_certificate = (protocol == "https" and hostname == "localhost"),
                        healthy = {
                          interval = bu.HEALTHCHECK_INTERVAL,
                          successes = nchecks,
                        },
                        unhealthy = {
                          interval = bu.HEALTHCHECK_INTERVAL,
                          http_failures = nchecks,
                        },
                      }
                    }
                  })
                  bu.add_target(bp, upstream_id, hostname, port1) -- port gets overridden at DNS resolution
                  local api_host = bu.add_api(bp, upstream_name, {
                    service_protocol = protocol
                  })
                  bu.end_testcase_setup(strategy, bp)

                  -- 1) server1 and server2 take requests
                  local oks, fails = bu.client_requests(bu.SLOTS, api_host)
                  -- server2 goes unhealthy
                  bu.direct_request(localhost, port2, "/unhealthy", protocol, hostname)
                  -- Wait until healthchecker detects
                  bu.poll_wait_address_health(upstream_id, hostname, port1, localhost, port2, "UNHEALTHY")

                  -- 2) server1 takes all requests
                  do
                    local o, f = bu.client_requests(bu.SLOTS, api_host)
                    oks = oks + o
                    fails = fails + f
                  end

                  -- server2 goes healthy again
                  bu.direct_request(localhost, port2, "/healthy", protocol, hostname)
                  -- Give time for healthchecker to detect
                  bu.poll_wait_address_health(upstream_id, hostname, port1, localhost, port2, "HEALTHY")

                  -- 3) server1 and server2 take requests again
                  do
                    local o, f = bu.client_requests(bu.SLOTS, api_host)
                    oks = oks + o
                    fails = fails + f
                  end

                  -- collect server results; hitcount
                  local count1 = server1:shutdown()
                  local count2 = server2:shutdown()

                  -- verify
                  assert.are.equal(bu.SLOTS * 2, count1.ok)
                  assert.are.equal(bu.SLOTS, count2.ok)
                  assert.are.equal(0, count1.fail)
                  assert.are.equal(0, count2.fail)

                  assert.are.equal(bu.SLOTS * 3, oks)
                  assert.are.equal(0, fails)
                end
              end)

              -- FIXME this test is flaky in CI only
              it("#flaky perform active health checks on targets that resolve to the same IP -- automatic recovery #" .. protocol, function()
                local fixtures = {
                  dns_mock = helpers.dns_mock.new()
                }

                fixtures.dns_mock:A {
                  name = "target1.test",
                  address = "127.0.0.1",
                }
                fixtures.dns_mock:A {
                  name = "target2.test",
                  address = "127.0.0.1",
                }

                -- restart Kong
                bu.begin_testcase_setup_update(strategy, bp)
                helpers.restart_kong({
                  database = strategy,
                  admin_listen = default_admin_listen,
                  proxy_listen = default_proxy_listen,
                  nginx_conf = "spec/fixtures/custom_nginx.template",
                  lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
                  db_update_frequency = 0.1,
                  stream_listen = "off",
                  plugins = "bundled,fail-once-auth",
                }, nil, fixtures)
                bu.end_testcase_setup(strategy, bp)

                for _, nchecks in ipairs({1,3}) do

                  local port1 = bu.gen_port()

                  -- setup target servers:
                  -- server2 will only respond for part of the test,
                  -- then server1 will take over.
                  local server1 = https_server.new(port1, {"target1.test", "target2.test"}, protocol)
                  server1:start()

                  -- configure healthchecks
                  bu.begin_testcase_setup(strategy, bp)
                  local upstream_name, upstream_id = bu.add_upstream(bp, {
                    healthchecks = bu.healthchecks_config {
                      active = {
                        type = protocol,
                        http_path = "/status",
                        https_verify_certificate = false,
                        healthy = {
                          interval = bu.HEALTHCHECK_INTERVAL,
                          successes = nchecks,
                        },
                        unhealthy = {
                          interval = bu.HEALTHCHECK_INTERVAL,
                          http_failures = nchecks,
                        },
                      }
                    }
                  })
                  bu.add_target(bp, upstream_id, "target1.test", port1)
                  bu.add_target(bp, upstream_id, "target2.test", port1)
                  local api_host = bu.add_api(bp, upstream_name, {
                    service_protocol = protocol
                  })

                  bu.end_testcase_setup(strategy, bp)

                  -- 1) target1 and target2 take requests
                  local oks, fails = bu.client_requests(bu.SLOTS, api_host)

                  -- target2 goes unhealthy
                  bu.direct_request(localhost, port1, "/unhealthy", protocol, "target2.test")
                  -- Wait until healthchecker detects
                  bu.poll_wait_health(upstream_id, "target2.test", port1, "UNHEALTHY")

                  -- 2) target1 takes all requests
                  do
                    local o, f = bu.client_requests(bu.SLOTS, api_host)
                    oks = oks + o
                    fails = fails + f
                  end

                  -- target2 goes healthy again
                  bu.direct_request(localhost, port1, "/healthy", protocol, "target2.test")
                  -- Give time for healthchecker to detect
                  bu.poll_wait_health(upstream_id, "target2.test", port1, "HEALTHY")

                  -- 3) server1 and server2 take requests again
                  do
                    local o, f = bu.client_requests(bu.SLOTS, api_host)
                    oks = oks + o
                    fails = fails + f
                  end

                  -- collect server results; hitcount
                  local results = server1:shutdown()
                  ---- verify
                  assert.are.equal(bu.SLOTS * 2, results["target1.test"].ok)
                  assert.are.equal(bu.SLOTS, results["target2.test"].ok)
                  assert.are.equal(0, results["target1.test"].fail)
                  assert.are.equal(0, results["target1.test"].fail)
                  assert.are.equal(bu.SLOTS * 3, oks)
                  assert.are.equal(0, fails)
                end
              end)
            end

            it("#flaky #db perform active health checks -- automatic recovery #stream", function()

              local port1 = bu.gen_port()
              local port2 = bu.gen_port()

              -- setup target servers:
              -- server2 will only respond for part of the test,
              -- then server1 will take over.
              local server1 = helpers.tcp_server(port1, {
                requests = 1000,
                prefix = "1 ",
              })
              local server2 = helpers.tcp_server(port2, {
                requests = 1000,
                prefix = "2 ",
              })
              ngx.sleep(0.1)

              -- configure healthchecks
              bu.begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = bu.add_upstream(bp, {
                healthchecks = bu.healthchecks_config {
                  active = {
                    type = "tcp",
                    healthy = {
                      interval = bu.HEALTHCHECK_INTERVAL,
                      successes = 1,
                    },
                    unhealthy = {
                      interval = bu.HEALTHCHECK_INTERVAL,
                      tcp_failures = 1,
                    },
                  }
                }
              })

              bu.add_target(bp, upstream_id, localhost, port1)
              bu.add_target(bp, upstream_id, localhost, port2)
              local _, service_id, route_id = bu.add_api(bp, upstream_name, {
                read_timeout = 500,
                write_timeout = 500,
                route_protocol = "tcp",
              })
              bu.end_testcase_setup(strategy, bp)

              finally(function()
                helpers.kill_tcp_server(port1)
                helpers.kill_tcp_server(port2)
                server1:join()
                server2:join()

                bp.routes:remove({ id = route_id })
                bp.services:remove({ id = service_id })
              end)

              ngx.sleep(0.5)

              -- 1) server1 and server2 take requests
              local ok1, ok2 = bu.tcp_client_requests(bu.SLOTS * 2, localhost, 9100)
              assert.same(bu.SLOTS, ok1)
              assert.same(bu.SLOTS, ok2)

              -- server2 goes unhealthy
              helpers.kill_tcp_server(port2)
              server2:join()

              -- Wait until healthchecker detects
              -- We cannot use bu.poll_wait_health because health endpoints
              -- are not currently available for stream routes.
              ngx.sleep(strategy == "cassandra" and 2 or 1)

              -- 2) server1 takes all requests
              ok1, ok2 = bu.tcp_client_requests(bu.SLOTS * 2, localhost, 9100)
              assert.same(bu.SLOTS * 2, ok1)
              assert.same(0, ok2)

              -- server2 goes healthy again
              server2 = helpers.tcp_server(port2, {
                requests = 1000,
                prefix = "2 ",
              })

              -- Give time for healthchecker to detect
              -- Again, we cannot use bu.poll_wait_health because health endpoints
              -- are not currently available for stream routes.
              ngx.sleep(strategy == "cassandra" and 2 or 1)

              -- 3) server1 and server2 take requests again
              ok1, ok2 = bu.tcp_client_requests(bu.SLOTS * 2, localhost, 9100)
              assert.same(bu.SLOTS, ok1)
              assert.same(bu.SLOTS, ok2)
            end)

            it("perform active health checks -- can detect before any proxy traffic", function()

              local nfails = 2
              local requests = bu.SLOTS * 2 -- go round the balancer twice
              local port1 = bu.gen_port()
              local port2 = bu.gen_port()
              -- setup target servers:
              -- server1 will respond all requests
              local server1 = https_server.new(port1, localhost)
              local server2 = https_server.new(port2, localhost)
              server1:start()
              server2:start()
              -- configure healthchecks
              bu.begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = bu.add_upstream(bp, {
                healthchecks = bu.healthchecks_config {
                  active = {
                    http_path = "/status",
                    healthy = {
                      interval = bu.HEALTHCHECK_INTERVAL,
                      successes = 1,
                    },
                    unhealthy = {
                      interval = bu.HEALTHCHECK_INTERVAL,
                      http_failures = nfails,
                      tcp_failures = nfails,
                    },
                  }
                }
              })
              bu.add_target(bp, upstream_id, localhost, port1)
              bu.add_target(bp, upstream_id, localhost, port2)
              local api_host = bu.add_api(bp, upstream_name)
              bu.end_testcase_setup(strategy, bp)

              -- server2 goes unhealthy before the first request
              bu.direct_request(localhost, port2, "/unhealthy")

              -- restart Kong
              bu.begin_testcase_setup_update(strategy, bp)
              helpers.restart_kong({
                database   = strategy,
                admin_listen = default_admin_listen,
                proxy_listen = default_proxy_listen,
                nginx_conf = "spec/fixtures/custom_nginx.template",
                lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
                db_update_frequency = 0.1,
                stream_listen = "off",
                plugins = "bundled,fail-once-auth",
              })
              bu.end_testcase_setup(strategy, bp)

              -- Give time for healthchecker to detect
              if mode == "ipv6" then
                bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "UNHEALTHY")
              else
                bu.poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")
              end

              -- server1 takes all requests

              local client_oks, client_fails = bu.client_requests(requests, api_host)

              -- collect server results; hitcount
              local results1 = server1:shutdown()
              local results2 = server2:shutdown()

              -- verify
              assert.are.equal(requests, results1.ok)
              assert.are.equal(0, results2.ok)
              assert.are.equal(0, results1.fail)
              assert.are.equal(0, results2.fail)

              assert.are.equal(requests, client_oks)
              assert.are.equal(0, client_fails)

            end)

            it("#flaky perform passive health checks -- manual recovery", function()

              for nfails = 1, 3 do
                -- configure healthchecks
                bu.begin_testcase_setup(strategy, bp)
                local upstream_name, upstream_id = bu.add_upstream(bp, {
                  healthchecks = bu.healthchecks_config {
                    passive = {
                      unhealthy = {
                        http_failures = nfails,
                      }
                    }
                  }
                })
                local port1 = bu.add_target(bp, upstream_id, localhost)
                local port2 = bu.add_target(bp, upstream_id, localhost)
                local api_host = bu.add_api(bp, upstream_name)
                bu.end_testcase_setup(strategy, bp)

                -- setup target servers:
                -- server2 will only respond for part of the test,
                -- then server1 will take over.
                local server1_oks = bu.SLOTS * 2 - nfails
                local server2_oks = bu.SLOTS
                local server1 = https_server.new(port1, localhost)
                local server2 = https_server.new(port2, localhost)
                server1:start()
                server2:start()

                -- 1) server1 and server2 take requests
                local oks, fails = bu.client_requests(bu.SLOTS, api_host)

                bu.direct_request(localhost, port2, "/unhealthy")

                -- 2) server1 takes all requests once server2 produces
                -- `nfails` failures
                do
                  local o, f = bu.client_requests(bu.SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- server2 is healthy again
                bu.direct_request(localhost, port2, "/healthy")

                -- manually bring it back using the endpoint
                if mode == "ipv6" then
                  -- TODO /upstreams does not understand shortened IPv6 addresses
                  bu.post_target_endpoint(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "healthy")
                  bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "HEALTHY")
                else
                  bu.post_target_endpoint(upstream_id, localhost, port2, "healthy")
                  bu.poll_wait_health(upstream_id, localhost, port2, "HEALTHY")
                end


                -- 3) server1 and server2 take requests again
                do
                  local o, f = bu.client_requests(bu.SLOTS, api_host)
                  oks = oks + o
                  fails = fails + f
                end

                -- collect server results; hitcount
                local results1 = server1:shutdown()
                local results2 = server2:shutdown()

                -- verify
                assert.are.equal(server1_oks, results1.ok)
                assert.are.equal(server2_oks, results2.ok)
                assert.are.equal(0, results1.fail)
                assert.are.equal(nfails, results2.fail)

                assert.are.equal(bu.SLOTS * 3 - nfails, oks)
                assert.are.equal(nfails, fails)
              end
            end)

            it("perform passive health checks -- manual shutdown", function()

              -- configure healthchecks
              bu.begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = bu.add_upstream(bp, {
                healthchecks = bu.healthchecks_config {
                  passive = {
                    unhealthy = {
                      http_failures = 1,
                    }
                  }
                }
              })
              local port1 = bu.add_target(bp, upstream_id, localhost)
              local port2 = bu.add_target(bp, upstream_id, localhost)
              local api_host = bu.add_api(bp, upstream_name)
              bu.end_testcase_setup(strategy, bp)

              -- setup target servers:
              -- server2 will only respond for part of the test,
              -- then server1 will take over.
              local server1 = https_server.new(port1, localhost)
              local server2 = https_server.new(port2, localhost)
              server1:start()
              server2:start()

              -- 1) server1 and server2 take requests
              local oks, fails = bu.client_requests(bu.SLOTS, api_host)

              -- manually bring it down using the endpoint
              if mode == "ipv6" then
                -- TODO /upstreams does not understand shortened IPv6 addresses
                bu.post_target_endpoint(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "unhealthy")
                bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "UNHEALTHY")
              else
                bu.post_target_endpoint(upstream_id, localhost, port2, "unhealthy")
                bu.poll_wait_health(upstream_id, localhost, port2, "UNHEALTHY")
              end

              -- 2) server1 takes all requests
              do
                local o, f = bu.client_requests(bu.SLOTS, api_host)
                oks = oks + o
                fails = fails + f
              end

              -- manually bring it back using the endpoint
              if mode == "ipv6" then
                -- TODO /upstreams does not understand shortened IPv6 addresses
                bu.post_target_endpoint(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "healthy")
                bu.poll_wait_health(upstream_id, "[0000:0000:0000:0000:0000:0000:0000:0001]", port2, "HEALTHY")
              else
                bu.post_target_endpoint(upstream_id, localhost, port2, "healthy")
                bu.poll_wait_health(upstream_id, localhost, port2, "HEALTHY")
              end

              -- 3) server1 and server2 take requests again
              do
                local o, f = bu.client_requests(bu.SLOTS, api_host)
                oks = oks + o
                fails = fails + f
              end

              -- collect server results; hitcount
              local results1 = server1:shutdown()
              local results2 = server2:shutdown()

              -- verify
              assert.are.equal(bu.SLOTS * 2, results1.ok)
              assert.are.equal(bu.SLOTS, results2.ok)
              assert.are.equal(0, results1.fail)
              assert.are.equal(0, results2.fail)

              assert.are.equal(bu.SLOTS * 3, oks)
              assert.are.equal(0, fails)

            end)

            it("perform passive health checks -- connection #timeouts", function()

              -- configure healthchecks
              bu.begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = bu.add_upstream(bp, {
                healthchecks = bu.healthchecks_config {
                  passive = {
                    unhealthy = {
                      timeouts = 1,
                    }
                  }
                }
              })
              local port1 = bu.add_target(bp, upstream_id, localhost)
              local port2 = bu.add_target(bp, upstream_id, localhost)
              local api_host = bu.add_api(bp, upstream_name, {
                read_timeout = 10,
                write_timeout = 10,
              })
              bu.end_testcase_setup(strategy, bp)

              -- setup target servers:
              -- server2 will only respond for half of the test
              -- then will timeout on the following request.
              -- Then server1 will take over.
              local server1_oks = bu.SLOTS * 1.5
              local server2_oks = bu.SLOTS / 2
              local server1 = https_server.new(port1, localhost)
              local server2 = https_server.new(port2, localhost)
              server1:start()
              server2:start()

              -- 1) server1 and server2 take requests
              local oks, fails = bu.client_requests(bu.SLOTS, api_host)

              bu.direct_request(localhost, port2, "/timeout")

              -- 2) server1 takes all requests once server2 produces
              -- `nfails` failures (even though server2 will be ready
              -- to respond 200 again after `nfails`)
              do
                local o, f = bu.client_requests(bu.SLOTS, api_host)
                oks = oks + o
                fails = fails + f
              end

              -- collect server results; hitcount
              local results1 = server1:shutdown()
              local results2 = server2:shutdown()

              -- verify
              assert.are.equal(server1_oks, results1.ok)
              assert.are.equal(server2_oks, results2.ok)
              assert.are.equal(0, results1.fail)
              assert.are.equal(1, results2.fail)

              assert.are.equal(bu.SLOTS * 2, oks)
              assert.are.equal(0, fails)
            end)

            stream_it("#flaky perform passive health checks -- #stream connection failure", function()

              -- configure healthchecks
              bu.begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = bu.add_upstream(bp, {
                healthchecks = bu.healthchecks_config {
                  passive = {
                    unhealthy = {
                      tcp_failures = 1,
                    }
                  }
                }
              })
              local port1 = bu.add_target(bp, upstream_id, localhost)
              local port2 = bu.add_target(bp, upstream_id, localhost)
              local _, service_id, route_id = bu.add_api(bp, upstream_name, {
                read_timeout = 50,
                write_timeout = 50,
                route_protocol = "tcp",
              })
              bu.end_testcase_setup(strategy, bp)

              finally(function()
                bp.routes:remove({ id = route_id })
                bp.services:remove({ id = service_id })
              end)

              -- setup target servers:
              -- server2 will only respond for half of the test and will shutdown.
              -- Then server1 will take over.
              local server1_oks = bu.SLOTS * 1.5
              local server2_oks = bu.SLOTS / 2
              local server1 = helpers.tcp_server(port1, {
                requests = server1_oks,
                prefix = "1 ",
              })
              local server2 = helpers.tcp_server(port2, {
                requests = server2_oks,
                prefix = "2 ",
              })
              ngx.sleep(strategy == "cassandra" and 2 or 1)

              -- server1 and server2 take requests
              -- server1 takes all requests once server2 fails
              local ok1, ok2, fails = bu.tcp_client_requests(bu.SLOTS * 2, localhost, 9100)

              -- finish up TCP server threads
              server1:join()
              server2:join()

              -- verify
              assert.are.equal(server1_oks, ok1)
              assert.are.equal(server2_oks, ok2)
              assert.are.equal(0, fails)
            end)

            -- #db == disabled for database=off, because healthcheckers
            -- are currently reset when a new configuration is loaded
            -- TODO enable this test when upstreams are preserved (not rebuild)
            -- across a declarative config updates.
            -- TODO marked as flaky as it fails only in CI
            it("#flaky #db perform passive health checks -- send #timeouts", function()

              -- configure healthchecks
              bu.begin_testcase_setup(strategy, bp)
              local upstream_name, upstream_id = bu.add_upstream(bp, {
                healthchecks = bu.healthchecks_config {
                  passive = {
                    unhealthy = {
                      http_failures = 0,
                      timeouts = 1,
                      tcp_failures = 0,
                    }
                  }
                }
              })
              local port1 = bu.add_target(bp, upstream_id, localhost)
              local api_host, service_id = bu.add_api(bp, upstream_name, {
                read_timeout = 10,
                retries = 0,
              })
              bu.end_testcase_setup(strategy, bp)

              local server1 = https_server.new(port1, localhost)
              server1:start()
              bu.direct_request(localhost, port1, "/timeout")

              local _, _, last_status = bu.client_requests(1, api_host)

              local results1 = server1:shutdown()
              assert.same(504, last_status)
              assert.same(0, results1.ok)
              assert.same(1, results1.fail)

              bu.begin_testcase_setup_update(strategy, bp)
              bu.patch_api(bp, service_id, nil, 60000)
              local port2 = bu.add_target(bp, upstream_id, localhost)
              bu.end_testcase_setup(strategy, bp)

              local server2 = https_server.new(port2, localhost)
              server2:start()

              _, _, last_status = bu.client_requests(bu.SLOTS, api_host)
              assert.same(200, last_status)

              local results2 = server2:shutdown()
              assert.same(bu.SLOTS, results2.ok)
              assert.same(0, results2.fail)
            end)

          end)

        end)

      end
    end)

  end)

  describe("Consistent-hashing #" .. strategy, function()
    local a_dns_entry_name = "consistent.hashing.test"

    lazy_setup(function()
      bp = bu.get_db_utils_for_dc_and_admin_api(strategy, {
        "routes",
        "services",
        "plugins",
        "upstreams",
        "targets",
      })

      local fixtures = {
        dns_mock = helpers.dns_mock.new()
      }

      fixtures.dns_mock:A {
        name = a_dns_entry_name,
        address = "127.0.0.1",
      }

      assert(helpers.start_kong({
        database   = strategy,
        dns_resolver = "127.0.0.1",
        admin_listen = default_admin_listen,
        proxy_listen = default_proxy_listen,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        db_update_frequency = DB_UPDATE_FREQUENCY,
        db_update_propagation = DB_UPDATE_PROPAGATION,
      }, nil, nil, fixtures))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("passive healthcheck", function()
      local total_requests = 9

      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        hash_on = "header",
        hash_on_header = "hashme",
        healthchecks = bu.healthchecks_config {
          passive = {
            type = "http",
            healthy = {
              successes = 1,
            },
            unhealthy = {
              http_failures = 1,
            },
          }
        }
      })
      local port1 = bu.add_target(bp, upstream_id, a_dns_entry_name)
      local port2 = bu.add_target(bp, upstream_id, a_dns_entry_name)
      local port3 = bu.add_target(bp, upstream_id, a_dns_entry_name)
      local api_host = bu.add_api(bp, upstream_name)
      bu.end_testcase_setup(strategy, bp)

      local server1 = https_server.new(port1, a_dns_entry_name)
      local server2 = https_server.new(port2, a_dns_entry_name)
      local server3 = https_server.new(port3, a_dns_entry_name)
      server1:start()
      server2:start()
      server3:start()

      bu.client_requests(total_requests, {
        ["Host"] = api_host,
        ["hashme"] = "just a value",
      })

      local count1 = server1:shutdown()
      local count2 = server2:shutdown()
      local count3 = server3:shutdown()

      assert(count1.total == 0 or count1.total == total_requests, "counts should either get 0 or all hits")
      assert(count2.total == 0 or count2.total == total_requests, "counts should either get 0 or all hits")
      assert(count3.total == 0 or count3.total == total_requests, "counts should either get 0 or all hits")
      assert.False(count1.total == count2.total == count3.total)

      local health = bu.get_balancer_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)
      assert.is_equal(health.data.health, "HEALTHY")

      -- restart the servers, but not the one which received the previous requests
      if count1.total == 0 then
        server1 = https_server.new(port1, a_dns_entry_name)
        server1:start()
      else
        server1 = nil
      end

      if count2.total == 0 then
        server2 = https_server.new(port2, a_dns_entry_name)
        server2:start()
      else
        server2 = nil
      end

      if count3.total == 0 then
        server3 = https_server.new(port3, a_dns_entry_name)
        server3:start()
      else
        server3 = nil
      end

      bu.client_requests(total_requests, {
        ["Host"] = api_host,
        ["hashme"] = "just a value",
      })

      if server1 ~= nil then
        server1:shutdown()
      end

      if server2 ~= nil then
        server2:shutdown()
      end

      if server3 ~= nil then
        server3:shutdown()
      end

      -- get updated health details
      health = bu.get_balancer_health(upstream_name)
      assert.is.table(health)
      assert.is.table(health.data)


      -- the server that received the requests in the first round,
      -- should be unhealthy now
      for _, host in ipairs(health.data.details.hosts) do
        if count1.total ~= 0 and host.port == port1 then
          assert.is_false(host.addresses[1].healthy)
          break
        elseif count2.total ~= 0 and host.port == port2 then
          assert.is_false(host.addresses[1].healthy)
          break
        elseif count3.total ~= 0 and host.port == port3 then
          assert.is_false(host.addresses[1].healthy)
          break
        end
      end

      -- the upstream should be healthy anyway
      assert.is_equal(health.data.health, "HEALTHY")
    end)

    -- FIXME this test fails on CI but should be ok
    it("#flaky active healthcheck", function()
      bu.begin_testcase_setup(strategy, bp)
      local upstream_name, upstream_id = bu.add_upstream(bp, {
        hash_on = "header",
        hash_on_header = "hashme",
        healthchecks = bu.healthchecks_config {
          active = {
            type = "http",
            http_path = "/status",
            healthy = {
              interval = bu.HEALTHCHECK_INTERVAL,
              successes = 1,
            },
            unhealthy = {
              interval = bu.HEALTHCHECK_INTERVAL,
              http_failures = 1,
            },
          }
        }
      })
      local port1 = bu.add_target(bp, upstream_id, "localhost")
      local port2 = bu.add_target(bp, upstream_id, "localhost")
      local port3 = bu.add_target(bp, upstream_id, "localhost")
      bu.add_api(bp, upstream_name)
      bu.end_testcase_setup(strategy, bp)

      local server1 = https_server.new(port1, "localhost")
      local server2 = https_server.new(port2, "localhost")
      local server3 = https_server.new(port3, "localhost")
      server1:start()
      server2:start()
      server3:start()

      ngx.sleep(bu.HEALTHCHECK_INTERVAL * 3)

      -- get all healthy servers
      local all_healthy = bu.get_balancer_health(upstream_name)

      -- tell server3 to be unhappy
      bu.direct_request("localhost", port3, "/unhealthy")

      -- wait active health check to run
      ngx.sleep(bu.HEALTHCHECK_INTERVAL * 3)

      -- get updated health details
      local not_so_healthy = bu.get_balancer_health(upstream_name)

      local count1 = server1:shutdown()
      local count2 = server2:shutdown()
      local count3 = server3:shutdown()

      assert(count1.status_ok > 0, "server1 should receive active health checks")
      assert(count1.status_fail == 0, "server1 should not fail on active health checks")
      assert(count2.status_ok > 0, "server2 should receive active health checks")
      assert(count2.status_fail == 0, "server should not fail on active health checks")
      assert(count3.status_ok > 0, "server3 should receive active health checks")
      assert(count3.status_fail > 0, "server3 should receive active health checks")

      assert.is.table(all_healthy)
      assert.is.table(all_healthy.data)
      assert.is.table(not_so_healthy)
      assert.is.table(not_so_healthy.data)

      -- all servers should be healthy on first run
      for _, host in ipairs(all_healthy.data.details.hosts) do
          assert.is_true(host.addresses[1].healthy)
      end
      -- tand he upstream should be healthy
      assert.is_equal(all_healthy.data.health, "HEALTHY")

      -- servers on ports 1 and 2 should be healthy, on port 3 should be unhealthy
      for _, host in ipairs(not_so_healthy.data.details.hosts) do
        if host.port == port1 then
          assert.is_true(host.addresses[1].healthy)
        elseif host.port == port2 then
          assert.is_true(host.addresses[1].healthy)
        elseif host.port == port3 then
          assert.is_false(host.addresses[1].healthy)
        end
      end
      -- the upstream should be healthy anyway
      assert.is_equal(not_so_healthy.data.health, "HEALTHY")
    end)

  end)

end
