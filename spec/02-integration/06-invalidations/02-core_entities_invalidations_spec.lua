local cjson        = require "cjson"
local helpers      = require "spec.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"


local POLL_INTERVAL = 0.1


local function assert_proxy_2_wait(request, res_status, res_headers)
  helpers.wait_until(function()
    local proxy_client_2 = helpers.http_client("127.0.0.1", 9000)
    finally(function()
      proxy_client_2:close()
    end)

    local res = proxy_client_2:send(request)
    if not res then
      return false
    end
    if res.status ~= res_status then
      return false
    end
    if res_headers then
      for k,v in pairs(res_headers) do
        if res.headers[k] ~= (v ~= ngx.null and v or nil) then
          return false
        end
      end
    end
    return true
  end, 30)
end


for _, strategy in helpers.each_strategy() do
  describe("core entities are invalidated with db [#" .. strategy .. "]", function()

    local admin_client_1
    local admin_client_2

    local proxy_client_1
    local proxy_client_2

    local service_fixture

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "snis",
        "certificates",
        "snis",
      })

      -- insert single fixture Service
      service_fixture = bp.services:insert()

      local db_update_propagation = strategy == "cassandra" and 0.1 or 0

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot1",
        database              = strategy,
        proxy_listen          = "0.0.0.0:8000, 0.0.0.0:8443 ssl",
        admin_listen          = "0.0.0.0:8001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
        nginx_conf            = "spec/fixtures/custom_nginx.template",
        router_update_frequency = POLL_INTERVAL,
      })

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot2",
        database              = strategy,
        proxy_listen          = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
        admin_listen          = "0.0.0.0:9001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
        router_update_frequency = POLL_INTERVAL,
      })

      admin_client_1 = helpers.http_client("127.0.0.1", 8001)
      admin_client_2 = helpers.http_client("127.0.0.1", 9001)
      proxy_client_1 = helpers.http_client("127.0.0.1", 8000)
      proxy_client_2 = helpers.http_client("127.0.0.1", 9000)
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot1", true)
      helpers.stop_kong("servroot2", true)
    end)

    before_each(function()
      admin_client_1 = helpers.http_client("127.0.0.1", 8001)
      admin_client_2 = helpers.http_client("127.0.0.1", 9001)
      proxy_client_1 = helpers.http_client("127.0.0.1", 8000)
      proxy_client_2 = helpers.http_client("127.0.0.1", 9000)
    end)

    after_each(function()
      admin_client_1:close()
      admin_client_2:close()
      proxy_client_1:close()
      proxy_client_2:close()
    end)

    ---------
    -- Routes
    ---------


    describe("Routes (router)", function()
      lazy_setup(function()
        -- populate cache with a miss on
        -- both nodes

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "example.com",
          }
        })
        assert.res_status(404, res_1)

        local res = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "example.com",
          }
        })
        assert.res_status(404, res)
      end)

      local route_fixture_id

      it("on create", function()
        local admin_res = assert(admin_client_1:send {
          method  = "POST",
          path    = "/routes",
          body    = {
            protocols = { "http" },
            hosts     = { "example.com" },
            service   = {
              id = service_fixture.id,
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.res_status(201, admin_res)
        local json = cjson.decode(body)
        route_fixture_id = json.id

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        do
          local res = assert(proxy_client_1:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              host = "example.com",
            }
          })
          assert.res_status(200, res)
        end

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "example.com",
          }
        }, 200)
      end)

      it("on update", function()
        local admin_res = assert(admin_client_1:send {
          method  = "PATCH",
          path    = "/routes/" .. route_fixture_id,
          body    = {
            methods = cjson.null,
            hosts   = { "updated-example.com" },
            paths   = cjson.null,
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(200, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        -- TEST: ensure new host value maps to our Service

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "updated-example.com",
          }
        })
        assert.res_status(200, res_1)

        -- TEST: ensure old host value does not map anywhere

        local res_1_old = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "example.com",
          }
        })
        assert.res_status(404, res_1_old)

        -- TEST: ensure new host value maps to our Service

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/",
          headers = {
            host = "updated-example.com",
          }
        }, 200)

        -- TEST: ensure old host value does not map anywhere

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/",
          headers = {
            host = "example.com",
          }
        }, 404)
      end)

      it("on delete", function()
        local admin_res = assert(admin_client_1:send {
          method = "DELETE",
          path   = "/routes/" .. route_fixture_id,
        })
        assert.res_status(204, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "updated-example.com",
          }
        })
        assert.res_status(404, res_1)

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/",
          headers = {
            host = "updated-example.com",
          }
        }, 404)
      end)
    end)


    -----------
    -- Services
    -----------


    describe("Services (router)", function()
      it("on update", function()
        local admin_res = assert(admin_client_1:send {
          method  = "POST",
          path    = "/routes",
          body    = {
            protocols = { "http" },
            hosts     = { "service.com" },
            service   = {
              id = service_fixture.id,
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, admin_res)

        -- populate cache on both nodes

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "service.com",
          }
        })
        assert.res_status(200, res_1)

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "service.com",
          }
        }, 200)

        -- update the Service

        admin_res = assert(admin_client_1:send {
          method = "PATCH",
          path   = "/services/" .. service_fixture.id,
          body   = {
            path = "/status/418",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(200, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "service.com",
          }
        })
        assert.res_status(418, res_1)

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/",
          headers = {
            host = "service.com",
          }
        }, 418)
      end)

      pending("on delete", function()
        -- Pending: at the time of this writing, deleting a Service with
        -- a Route still attached to it is impossible, and deleting a Route
        -- is already tested above, hence, this test is disabled for now.

        local admin_res = assert(admin_client_1:send {
          method = "DELETE",
          path   = "/services/" .. service_fixture.id,
        })
        assert.res_status(204, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "service.com",
          }
        })
        assert.res_status(404, res_1)

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/",
          headers = {
            host = "service.com",
          }
        }, 404)
      end)
    end)

    -------------------
    -- ssl_certificates
    -------------------

    describe("ssl_certificates / snis", function()

      local function get_cert(port, sn)
        local pl_utils = require "pl.utils"

        local cmd = [[
          echo "" | openssl s_client \
          -showcerts \
          -connect 127.0.0.1:%d \
          -servername %s \
        ]]

        local _, _, stderr = pl_utils.executeex(string.format(cmd, port, sn))

        return stderr
      end

      lazy_setup(function()
        -- populate cache with misses on both nodes
        local cert_1 = get_cert(8443, "ssl-example.com")
        local cert_2 = get_cert(9443, "ssl-example.com")
        local cert_wildcard_1 = get_cert(8443, "test.wildcard.com")
        local cert_wildcard_2 = get_cert(9443, "test.wildcard.com")
        local cert_wildcard_3 = get_cert(8443, "wildcard.org")
        local cert_wildcard_4 = get_cert(9443, "wildcard.org")

        -- if you get an error when running these, you likely have an outdated version of openssl installed
        -- to update in osx: https://github.com/Kong/kong/pull/2776#issuecomment-320275043
        assert.certificate(cert_1).has.cn("localhost")
        assert.certificate(cert_2).has.cn("localhost")
        assert.certificate(cert_wildcard_1).has.cn("localhost")
        assert.certificate(cert_wildcard_2).has.cn("localhost")
        assert.certificate(cert_wildcard_3).has.cn("localhost")
        assert.certificate(cert_wildcard_4).has.cn("localhost")
      end)

      it("on certificate+sni create", function()
        local admin_res = admin_client_1:post("/certificates", {
          body   = {
            cert = ssl_fixtures.cert,
            key  = ssl_fixtures.key,
            snis = { "ssl-example.com" },
          },
          headers = { ["Content-Type"] = "application/json" }
        })
        assert.res_status(201, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local cert_1 = get_cert(8443, "ssl-example.com")
        assert.certificate(cert_1).has.cn("ssl-example.com")

        helpers.wait_until(function()
          local cert_2 = get_cert(9443, "ssl-example.com")
          return pcall(function()
            assert.certificate(cert_2).has.cn("ssl-example.com")
          end)
        end)
      end)

      it("on certificate delete+re-creation", function()
        -- TODO: PATCH update are currently not possible
        -- with the admin API because snis have their name as their
        -- primary key and the DAO has limited support for such updates.

        local admin_res = admin_client_1:delete("/certificates/ssl-example.com")
        assert.res_status(204, admin_res)

        local admin_res = admin_client_1:post("/certificates", {
          body   = {
            cert = ssl_fixtures.cert,
            key  = ssl_fixtures.key,
            snis = { "new-ssl-example.com" },
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local cert_1a = get_cert(8443, "ssl-example.com")
        assert.certificate(cert_1a).has.cn("localhost")

        local cert_1b = get_cert(8443, "new-ssl-example.com")
        assert.certificate(cert_1b).has.cn("ssl-example.com")

        helpers.wait_until(function()
          local cert_2a = get_cert(9443, "ssl-example.com")
          return pcall(function()
            assert.certificate(cert_2a).has.cn("localhost")
          end)
        end)

        local cert_2b = get_cert(9443, "new-ssl-example.com")
        assert.certificate(cert_2b).has.cn("ssl-example.com")
      end)

      it("on certificate update", function()
        -- update our certificate *without* updating the
        -- attached sni

        local admin_res = assert(admin_client_1:send {
          method = "PATCH",
          path   = "/certificates/new-ssl-example.com",
          body   = {
            cert = ssl_fixtures.cert_alt,
            key  = ssl_fixtures.key_alt,
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(200, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local cert_1 = get_cert(8443, "new-ssl-example.com")
        assert.certificate(cert_1).has.cn("ssl-alt.com")

        helpers.wait_until(function()
          local cert_2 = get_cert(9443, "new-ssl-example.com")
          return pcall(function()
            assert.certificate(cert_2).has.cn("ssl-alt.com")
          end)
        end)
      end)

      it("on sni update via id #flaky", function()
        local admin_res = admin_client_1:get("/snis")
        local body = assert.res_status(200, admin_res)
        local sni = assert(cjson.decode(body).data[1])

        local admin_res = admin_client_1:patch("/snis/" .. sni.id, {
          body    = { name = "updated-sn-via-id.com" },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(200, admin_res)

        local cert_1_old = get_cert(8443, "new-ssl-example.com")
        assert.certificate(cert_1_old).has.cn("localhost")

        local cert_1_new = get_cert(8443, "updated-sn-via-id.com")
        assert.certificate(cert_1_new).has.cn("ssl-alt.com")

        helpers.wait_until(function()
          local cert_2_old = get_cert(9443, "new-ssl-example.com")
          return pcall(function()
            assert.certificate(cert_2_old).has.cn("localhost")
          end)
        end)

        local cert_2_new = get_cert(9443, "updated-sn-via-id.com")
        assert.certificate(cert_2_new).has.cn("ssl-alt.com")
      end)

      it("on sni update via name #flaky", function()
        local admin_res = admin_client_1:patch("/snis/updated-sn-via-id.com", {
          body    = { name = "updated-sn.com" },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(200, admin_res)

        local cert_1_old = get_cert(8443, "updated-sn-via-id.com")
        assert.certificate(cert_1_old).has.cn("localhost")

        local cert_1_new = get_cert(8443, "updated-sn.com")
        assert.certificate(cert_1_new).has.cn("ssl-alt.com")

        helpers.wait_until(function()
          local cert_2_old = get_cert(9443, "updated-sn-via-id.com")
          return pcall(function()
            assert.certificate(cert_2_old).has.cn("localhost")
          end)
        end)

        local cert_2_new = get_cert(9443, "updated-sn.com")
        assert.certificate(cert_2_new).has.cn("ssl-alt.com")
      end)

      it("on certificate delete #flaky", function()
        -- delete our certificate

        local admin_res = admin_client_1:delete("/certificates/updated-sn.com")
        assert.res_status(204, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local cert_1 = get_cert(8443, "updated-sn.com")
        assert.certificate(cert_1).has.cn("localhost")

        helpers.wait_until(function()
          local cert_2 = get_cert(9443, "updated-sn.com")
          return pcall(function()
            assert.certificate(cert_2).has.cn("localhost")
          end)
        end)
      end)

      describe("wildcard snis", function()
        it("on create", function()
          local admin_res = admin_client_1:post("/certificates", {
            body   = {
              cert = ssl_fixtures.cert_alt,
              key  = ssl_fixtures.key_alt,
              snis = { "*.wildcard.com" },
            },
            headers = { ["Content-Type"] = "application/json" }
          })
          assert.res_status(201, admin_res)

          local admin_res = admin_client_1:post("/certificates", {
            body   = {
              cert = ssl_fixtures.cert_alt_alt,
              key  = ssl_fixtures.key_alt_alt,
              snis = { "wildcard.*" },
            },
            headers = { ["Content-Type"] = "application/json" }
          })
          assert.res_status(201, admin_res)

          -- no need to wait for workers propagation (lua-resty-worker-events)
          -- because our test instance only has 1 worker

          local cert = get_cert(8443, "test.wildcard.com")
          assert.certificate(cert).has.cn("ssl-alt.com")
          cert = get_cert(8443, "test2.wildcard.com")
          assert.certificate(cert).has.cn("ssl-alt.com")

          helpers.wait_until(function()
            cert = get_cert(9443, "test.wildcard.com")
            return pcall(function()
              assert.certificate(cert).has.cn("ssl-alt.com")
            end)
          end)

          helpers.wait_until(function()
            cert = get_cert(9443, "test2.wildcard.com")
            return pcall(function()
              assert.certificate(cert).has.cn("ssl-alt.com")
            end)
          end)

          cert = get_cert(8443, "wildcard.org")
          assert.certificate(cert).has.cn("ssl-alt-alt.com")
          cert = get_cert(8443, "wildcard.com")
          assert.certificate(cert).has.cn("ssl-alt-alt.com")
        end)

        it("on certificate update", function()
          -- update our certificate *without* updating the
          -- attached sni

          local admin_res = assert(admin_client_1:send {
            method = "PATCH",
            path   = "/certificates/%2A.wildcard.com",
            body   = {
              cert = ssl_fixtures.cert_alt_alt,
              key  = ssl_fixtures.key_alt_alt,
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.res_status(200, admin_res)

          -- no need to wait for workers propagation (lua-resty-worker-events)
          -- because our test instance only has 1 worker

          local cert = get_cert(8443, "test.wildcard.com")
          assert.certificate(cert).has.cn("ssl-alt-alt.com")
          cert = get_cert(8443, "test2.wildcard.com")
          assert.certificate(cert).has.cn("ssl-alt-alt.com")

          helpers.wait_until(function()
            local cert1 = get_cert(9443, "test.wildcard.com")
            local cert2 = get_cert(9443, "test2.wildcard.com")
            return pcall(function()
              assert.certificate(cert1).has.cn("ssl-alt-alt.com")
              assert.certificate(cert2).has.cn("ssl-alt-alt.com")
            end)
          end)
        end)

        it("on sni update via id", function()
          local admin_res = admin_client_1:get("/snis/%2A.wildcard.com")
          local body = assert.res_status(200, admin_res)
          local sni = assert(cjson.decode(body))

          local admin_res = admin_client_1:patch("/snis/" .. sni.id, {
            body    = { name = "*.wildcard_updated.com" },
            headers = { ["Content-Type"] = "application/json" },
          })
          assert.res_status(200, admin_res)

          local cert_1_old = get_cert(8443, "test.wildcard.com")
          assert.certificate(cert_1_old).has.cn("localhost")
          cert_1_old = get_cert(8443, "test2.wildcard.com")
          assert.certificate(cert_1_old).has.cn("localhost")

          local cert_1_new = get_cert(8443, "test.wildcard_updated.com")
          assert.certificate(cert_1_new).has.cn("ssl-alt-alt.com")
          cert_1_new = get_cert(8443, "test2.wildcard_updated.com")
          assert.certificate(cert_1_new).has.cn("ssl-alt-alt.com")

          helpers.wait_until(function()
            local cert_2_old_1 = get_cert(9443, "test.wildcard.com")
            local cert_2_old_2 = get_cert(9443, "test2.wildcard.com")
            return pcall(function()
              assert.certificate(cert_2_old_1).has.cn("localhost")
              assert.certificate(cert_2_old_2).has.cn("localhost")
            end)
          end)

          local cert_2_new = get_cert(9443, "test.wildcard_updated.com")
          assert.certificate(cert_2_new).has.cn("ssl-alt-alt.com")
          cert_2_new = get_cert(9443, "test2.wildcard_updated.com")
          assert.certificate(cert_2_new).has.cn("ssl-alt-alt.com")
        end)

        it("on sni update via name", function()
          local admin_res = admin_client_1:patch("/snis/%2A.wildcard_updated.com", {
            body    = { name = "*.wildcard.org" },
            headers = { ["Content-Type"] = "application/json" },
          })
          assert.res_status(200, admin_res)

          local cert_1_old = get_cert(8443, "test.wildcard_updated.com")
          assert.certificate(cert_1_old).has.cn("localhost")
          cert_1_old = get_cert(8443, "test2.wildcard_updated.com")
          assert.certificate(cert_1_old).has.cn("localhost")

          local cert_1_new = get_cert(8443, "test.wildcard.org")
          assert.certificate(cert_1_new).has.cn("ssl-alt-alt.com")
          cert_1_new = get_cert(8443, "test2.wildcard.org")
          assert.certificate(cert_1_new).has.cn("ssl-alt-alt.com")

          helpers.wait_until(function()
            local cert_2_old_1 = get_cert(9443, "test.wildcard_updated.com")
            local cert_2_old_2 = get_cert(9443, "test2.wildcard_updated.com")
            return pcall(function()
              assert.certificate(cert_2_old_1).has.cn("localhost")
              assert.certificate(cert_2_old_2).has.cn("localhost")
            end)
          end)

          local cert_2_new = get_cert(9443, "test.wildcard.org")
          assert.certificate(cert_2_new).has.cn("ssl-alt-alt.com")
          cert_2_new = get_cert(9443, "test2.wildcard.org")
          assert.certificate(cert_2_new).has.cn("ssl-alt-alt.com")
        end)

        it("on certificate delete", function()
          -- delete our certificate

          local admin_res = admin_client_1:delete("/certificates/%2A.wildcard.org")
          assert.res_status(204, admin_res)

          -- no need to wait for workers propagation (lua-resty-worker-events)
          -- because our test instance only has 1 worker

          local cert_1 = get_cert(8443, "test.wildcard.org")
          assert.certificate(cert_1).has.cn("localhost")
          cert_1 = get_cert(8443, "test2.wildcard.org")
          assert.certificate(cert_1).has.cn("localhost")

          helpers.wait_until(function()
            local cert_2_1 = get_cert(9443, "test.wildcard.org")
            local cert_2_2 = get_cert(9443, "test2.wildcard.org")
            return pcall(function()
              assert.certificate(cert_2_1).has.cn("localhost")
              assert.certificate(cert_2_2).has.cn("localhost")
            end)
          end)
        end)
      end)
    end)

    ----------
    -- plugins
    ----------

    describe("plugins (per API)", function()
      local service_plugin_id

      it("on create", function()
        -- create Service

        local admin_res = assert(admin_client_1:send {
          method = "POST",
          path   = "/services",
          body   = {
            protocol = "http",
            host     = helpers.mock_upstream_host,
            port     = helpers.mock_upstream_port,
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.res_status(201, admin_res)
        local service_fixture = cjson.decode(body)

        -- create Route

        local admin_res = assert(admin_client_1:send {
          method  = "POST",
          path    = "/routes",
          body    = {
            protocols = { "http" },
            hosts     = { "dummy.com" },
            service   = {
              id = service_fixture.id,
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        -- populate cache with a miss on
        -- both nodes

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)
        assert.is_nil(res_1.headers["Dummy-Plugin"])

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        }, 200, { ["Dummy-Plugin"] = ngx.null })

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        }, 200, { ["Dummy-Plugin"] = ngx.null })

        -- create Plugin

        local admin_res_plugin = assert(admin_client_1:send {
          method = "POST",
          path   = "/plugins",
          body   = {
            name    = "dummy",
            service = { id = service_fixture.id },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.res_status(201, admin_res_plugin)
        local plugin = cjson.decode(body)
        service_plugin_id = assert(plugin.id, "could not get plugin id from " .. body)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker
        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)
        assert.equal("1", res_1.headers["Dummy-Plugin"])

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        }, 200, { ["Dummy-Plugin"] = "1" })
      end)

      it("on update", function()
        local admin_res_plugin = assert(admin_client_1:send {
          method = "PATCH",
          path   = "/plugins/" .. service_plugin_id,
          body   = {
            config = {
              resp_header_value = "2",
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(200, admin_res_plugin)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)
        assert.equal("2", res_1.headers["Dummy-Plugin"])

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        }, 200, { ["Dummy-Plugin"] = "2" })
      end)

      it("on delete", function()
        local admin_res_plugin = assert(admin_client_1:send {
          method = "DELETE",
          path   = "/plugins/" .. service_plugin_id,
        })
        assert.res_status(204, admin_res_plugin)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)
        assert.is_nil(res_1.headers["Dummy-Plugin"])

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        }, 200, { ["Dummy-Plugin"] = ngx.null })
      end)
    end)


    describe("plugins (global)", function()
      local global_dummy_plugin_id

      it("on create", function()
        -- populate cache with a miss on
        -- both nodes

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)
        assert.is_nil(res_1.headers["Dummy-Plugin"])

        do
          local res = assert(proxy_client_2:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              host = "dummy.com",
            }
          })
          assert.res_status(200, res)
          assert.is_nil(res.headers["Dummy-Plugin"])
        end

        local admin_res_plugin = assert(admin_client_1:send {
          method = "POST",
          path   = "/plugins",
          body   = {
            name = "dummy",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.res_status(201, admin_res_plugin)
        local plugin = cjson.decode(body)
        global_dummy_plugin_id = assert(plugin.id)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)
        assert.equal("1", res_1.headers["Dummy-Plugin"])

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        }, 200, { ["Dummy-Plugin"] = "1" })
      end)

      it("on delete", function()
        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)
        assert.equal("1", res_1.headers["Dummy-Plugin"])

        local admin_res = assert(admin_client_1:send {
          method = "DELETE",
          path   = "/plugins/" .. global_dummy_plugin_id,
        })
        assert.res_status(204, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)
        assert.is_nil(res_1.headers["Dummy-Plugin"])

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        }, 200, { ["Dummy-Plugin"] = ngx.null })
      end)
    end)
  end)

  -- declarative_config directive should be ignored in database tests:
  -- regression test for #4508.
  describe("declarative_config is ignored in DB mode [#" .. strategy .. "]", function()

    local admin_client_1
    local admin_client_2

    local proxy_client_1
    local proxy_client_2

    local service_fixture

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "certificates",
        "snis",
      })

      -- insert single fixture Service
      service_fixture = bp.services:insert()

      local db_update_propagation = strategy == "cassandra" and 0.1 or 0

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot1",
        database              = strategy,
        proxy_listen          = "0.0.0.0:8000, 0.0.0.0:8443 ssl",
        admin_listen          = "0.0.0.0:8001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
        nginx_conf            = "spec/fixtures/custom_nginx.template",
        declarative_config    = "ignore-me.yml",
      })

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot2",
        database              = strategy,
        proxy_listen          = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
        admin_listen          = "0.0.0.0:9001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
        declarative_config    = "ignore-me.yml",
      })

      admin_client_1 = helpers.http_client("127.0.0.1", 8001)
      admin_client_2 = helpers.http_client("127.0.0.1", 9001)
      proxy_client_1 = helpers.http_client("127.0.0.1", 8000)
      proxy_client_2 = helpers.http_client("127.0.0.1", 9000)
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot1", true)
      helpers.stop_kong("servroot2", true)
    end)

    before_each(function()
      admin_client_1 = helpers.http_client("127.0.0.1", 8001)
      admin_client_2 = helpers.http_client("127.0.0.1", 9001)
      proxy_client_1 = helpers.http_client("127.0.0.1", 8000)
      proxy_client_2 = helpers.http_client("127.0.0.1", 9000)
    end)

    after_each(function()
      admin_client_1:close()
      admin_client_2:close()
      proxy_client_1:close()
      proxy_client_2:close()
    end)

    describe("propagation works correctly", function()
      lazy_setup(function()
        -- populate cache with a miss on
        -- both nodes

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "propagation.test",
          }
        })
        assert.res_status(404, res_1)

        local res = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "propagation.test",
          }
        })
        assert.res_status(404, res)
      end)

      it("on create", function()
        local admin_res = assert(admin_client_1:send {
          method  = "POST",
          path    = "/routes",
          body    = {
            protocols = { "http" },
            hosts     = { "propagation.test" },
            service   = {
              id = service_fixture.id,
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(201, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "propagation.test",
          }
        })
        assert.res_status(200, res_1)

        assert_proxy_2_wait({
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "propagation.test",
          }
        }, 200)
      end)
    end)
  end)

  describe("core entities invalidations [#" .. strategy .. "]", function()
    local admin_client

    local proxy_client_1
    local proxy_client_2

    local wait_for_propagation

    local service
    local service_cache_key

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, {
        "invalidations"
      })

      service = bp.services:insert()
      service_cache_key = db.services:cache_key(service)

      bp.routes:insert {
        paths   = { "/" },
        service = service,
      }

      bp.plugins:insert {
        name    = "invalidations",
        service = { id = service.id },
      }

      local db_update_propagation = strategy == "cassandra" and 0.1 or 0

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot1",
        database              = strategy,
        plugins               = "invalidations",
        proxy_listen          = "0.0.0.0:8000, 0.0.0.0:8443 ssl",
        admin_listen          = "0.0.0.0:8001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
        nginx_conf            = "spec/fixtures/custom_nginx.template",
      })

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot2",
        database              = strategy,
        plugins               = "invalidations",
        proxy_listen          = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
        admin_listen          = "off",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
      })

      wait_for_propagation = function()
        ngx.sleep(POLL_INTERVAL * 2 + db_update_propagation * 2)
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot1", true)
      helpers.stop_kong("servroot2", true)
    end)

    before_each(function()
      admin_client = helpers.http_client("127.0.0.1", 8001)
      proxy_client_1 = helpers.http_client("127.0.0.1", 8000)
      proxy_client_2 = helpers.http_client("127.0.0.1", 9000)

    end)

    after_each(function()
      admin_client:close()
      proxy_client_1:close()
      proxy_client_2:close()
    end)

    -----------
    -- Services
    -----------

    describe("Services", function()
      it("#flaky raises correct number of invalidation events", function()
        local admin_res = assert(admin_client:send {
          method = "PATCH",
          path   = "/services/" .. service.id,
          body   = {
            path = "/new-path",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(200, admin_res)

        wait_for_propagation()

        local proxy_res = assert(proxy_client_1:get("/"))
        local body = assert.res_status(200, proxy_res)
        local json = cjson.decode(body)

        assert.equal(nil, json[service_cache_key])

        local proxy_res = assert(proxy_client_2:get("/"))
        local body = assert.res_status(200, proxy_res)
        local json = cjson.decode(body)

        assert.equal(1, json[service_cache_key])
      end)
    end)
  end)
end
