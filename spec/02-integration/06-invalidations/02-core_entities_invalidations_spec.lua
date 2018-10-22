local cjson        = require "cjson"
local helpers      = require "spec.helpers"
local migrations   = require "kong.cmd.utils.migrations"
local ssl_fixtures = require "spec.fixtures.ssl"


local POLL_INTERVAL = 0.3


for _, strategy in helpers.each_strategy() do
  describe("core entities are invalidated with db [#" .. strategy .. "]", function()

    local admin_client_1
    local admin_client_2

    local proxy_client_1
    local proxy_client_2

    local wait_for_propagation

    local service_fixture

    setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "apis",
        "routes",
        "services",
        "plugins",
        "certificates",
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
      })

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot2",
        database              = strategy,
        proxy_listen          = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
        admin_listen          = "0.0.0.0:9001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
      })

      admin_client_1 = helpers.http_client("127.0.0.1", 8001)
      admin_client_2 = helpers.http_client("127.0.0.1", 9001)
      proxy_client_1 = helpers.http_client("127.0.0.1", 8000)
      proxy_client_2 = helpers.http_client("127.0.0.1", 9000)

      wait_for_propagation = function()
        ngx.sleep(POLL_INTERVAL * 2 + db_update_propagation * 2)
      end
    end)

    teardown(function()
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
      setup(function()
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

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "example.com",
          }
        })
        assert.res_status(404, res_2)
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

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "example.com",
          }
        })
        assert.res_status(200, res_1)


        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "example.com",
          }
        })
        assert.res_status(200, res_2)
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

        wait_for_propagation()

        -- TEST: ensure new host value maps to our Service

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "updated-example.com",
          }
        })
        assert.res_status(200, res_2)

        -- TEST: ensure old host value does not map anywhere

        local res_2_old = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "example.com",
          }
        })
        assert.res_status(404, res_2_old)
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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "updated-example.com",
          }
        })
        assert.res_status(404, res_2)
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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "service.com",
          }
        })
        assert.res_status(200, res_2)

        -- update the Service

        local admin_res = assert(admin_client_1:send {
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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "service.com",
          }
        })
        assert.res_status(418, res_2)
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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "service.com",
          }
        })
        assert.res_status(404, res_2)
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

      setup(function()
        -- populate cache with a miss on
        -- both nodes
        local cert_1 = get_cert(8443, "ssl-example.com")
        local cert_2 = get_cert(9443, "ssl-example.com")

        -- if you get an error when running these, you likely have an outdated version of openssl installed
        -- to update in osx: https://github.com/Kong/kong/pull/2776#issuecomment-320275043
        assert.matches("CN%s*=%s*localhost", cert_1)
        assert.matches("CN%s*=%s*localhost", cert_2)
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
        assert.matches("CN%s*=%s*ssl%-example.com", cert_1)

        wait_for_propagation()

        local cert_2 = get_cert(9443, "ssl-example.com")
        assert.matches("CN%s*=%s*ssl%-example.com", cert_2)
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
        assert.matches("CN%s*=%s*localhost", cert_1a)

        local cert_1b = get_cert(8443, "new-ssl-example.com")
        assert.matches("CN%s*=%s*ssl%-example.com", cert_1b)

        wait_for_propagation()

        local cert_2a = get_cert(9443, "ssl-example.com")
        assert.matches("CN%s*=%s*localhost", cert_2a)

        local cert_2b = get_cert(9443, "new-ssl-example.com")
        assert.matches("CN%s*=%s*ssl%-example.com", cert_2b)
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
        assert.matches("CN%s*=%s*ssl%-alt.com", cert_1)

        wait_for_propagation()

        local cert_2 = get_cert(9443, "new-ssl-example.com")
        assert.matches("CN%s*=%s*ssl%-alt.com", cert_2)
      end)

      it("on sni update via id", function()
        local admin_res = admin_client_1:get("/snis")
        local body = assert.res_status(200, admin_res)
        local sni = assert(cjson.decode(body).data[1])

        local admin_res = admin_client_1:patch("/snis/" .. sni.id, {
          body    = { name = "updated-sn-via-id.com" },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(200, admin_res)

        local cert_1_old = get_cert(8443, "new-ssl-example.com")
        assert.matches("CN%s*=%s*localhost", cert_1_old)

        local cert_1_new = get_cert(8443, "updated-sn-via-id.com")
        assert.matches("CN%s*=%s*ssl%-alt.com", cert_1_new)

        wait_for_propagation()

        local cert_2_old = get_cert(9443, "new-ssl-example.com")
        assert.matches("CN%s*=%s*localhost", cert_2_old)

        local cert_2_new = get_cert(9443, "updated-sn-via-id.com")
        assert.matches("CN%s*=%s*ssl%-alt.com", cert_2_new)
      end)

      it("on sni update via name", function()
        local admin_res = admin_client_1:patch("/snis/updated-sn-via-id.com", {
          body    = { name = "updated-sn.com" },
          headers = { ["Content-Type"] = "application/json" },
        })
        assert.res_status(200, admin_res)

        local cert_1_old = get_cert(8443, "updated-sn-via-id.com")
        assert.matches("CN%s*=%s*localhost", cert_1_old)

        local cert_1_new = get_cert(8443, "updated-sn.com")
        assert.matches("CN%s*=%s*ssl%-alt.com", cert_1_new)

        wait_for_propagation()

        local cert_2_old = get_cert(9443, "updated-sn-via-id.com")
        assert.matches("CN%s*=%s*localhost", cert_2_old)

        local cert_2_new = get_cert(9443, "updated-sn.com")
        assert.matches("CN%s*=%s*ssl%-alt.com", cert_2_new)
      end)

      it("on certificate delete", function()
        -- delete our certificate

        local admin_res = admin_client_1:delete("/certificates/updated-sn.com")
        assert.res_status(204, admin_res)

        -- no need to wait for workers propagation (lua-resty-worker-events)
        -- because our test instance only has 1 worker

        local cert_1 = get_cert(8443, "updated-sn.com")
        assert.matches("CN%s*=%s*localhost", cert_1)

        wait_for_propagation()

        local cert_2 = get_cert(9443, "updated-sn.com")
        assert.matches("CN%s*=%s*localhost", cert_2)
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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)
        assert.is_nil(res_2.headers["Dummy-Plugin"])

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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)
        assert.equal("1", res_2.headers["Dummy-Plugin"])
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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)
        assert.equal("2", res_2.headers["Dummy-Plugin"])
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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)
        assert.is_nil(res_2.headers["Dummy-Plugin"])
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

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)
        assert.is_nil(res_2.headers["Dummy-Plugin"])

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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)
        assert.equal("1", res_2.headers["Dummy-Plugin"])
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

        wait_for_propagation()

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)
        assert.is_nil(res_2.headers["Dummy-Plugin"])
      end)
    end)

    describe("#schema state invalidated db [#" .. strategy .. "]", function()
      pending("on reset", function()
      end)

      pending("on bootstrap", function()
      end)

      it("on up", function()
        local res_1 = admin_client_1:get("/cache/migrations:schema_state")
        error(res_1)

        --migrations.up()

      end)
    end)
  end)
end
