local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"


for _, strategy in helpers.each_strategy() do

  describe("Plugins triggering [#" .. strategy .. "]", function()
    local proxy_client
    local db
    local dao
    local bp

    setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)

      local consumer1 = bp.consumers:insert {
        username = "consumer1"
      }

      bp.keyauth_credentials:insert {
        key         = "secret1",
        consumer_id = consumer1.id
      }

      local consumer2 = bp.consumers:insert {
        username = "consumer2"
      }

      bp.keyauth_credentials:insert {
        key         = "secret2",
        consumer_id = consumer2.id
      }

      local consumer3 = bp.consumers:insert {
        username = "anonymous"
      }

      -- Global configuration
      local service1 = bp.services:insert {
        name = "global1",
      }

      bp.routes:insert {
        hosts     = { "global1.com" },
        protocols = { "http" },
        service   = service1,
      }
      bp.plugins:insert {
        name   = "key-auth",
        config = {},
      }
      bp.plugins:insert {
        name   = "rate-limiting",
        config = {
          hour = 1,
        },
      }

      -- API Specific Configuration
      local service2 = bp.services:insert {
        name = "api1",
      }

      local route1 = bp.routes:insert {
        hosts     = { "api1.com" },
        protocols = { "http" },
        service   = service2,
      }

      bp.plugins:insert {
        name       = "rate-limiting",
        route_id   = route1.id,
        service_id = service2.id,
        config     = {
          hour     = 2,
        },
      }

      -- Consumer Specific Configuration
      bp.plugins:insert {
        name        = "rate-limiting",
        consumer_id = consumer2.id,
        config      = {
          hour      = 3,
        },
      }

      -- API and Consumer Configuration
      local service3 = assert(bp.services:insert {
        name = "api2",
      })

      local route2 = bp.routes:insert {
        hosts     = { "api2.com" },
        protocols = { "http" },
        service   = service3,
      }

      bp.plugins:insert {
        name        = "rate-limiting",
        route_id    = route2.id,
        consumer_id = consumer2.id,
        config      = {
          hour      = 4,
        },
      }

      -- API with anonymous configuration
      local service4 = bp.services:insert {
        name = "api3",
      }

      local route3 = bp.routes:insert {
        hosts     = { "api3.com" },
        protocols = { "http" },
        service   = service4,
      }

      bp.plugins:insert {
        name        = "key-auth",
        config      = {
          anonymous = consumer3.id,
        },
        route_id    = route3.id,
        service_id  = service4.id,
      }

      bp.plugins:insert {
        name        = "rate-limiting",
        route_id    = route3.id,
        service_id  = service4.id,
        consumer_id = consumer3.id,
        config      = {
          hour      = 5,
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    teardown(function()
      if proxy_client then proxy_client:close() end
      helpers.stop_kong()
    end)

    it("checks global configuration without credentials", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = { Host = "global1.com" }
      })
      assert.res_status(401, res)
    end)

    it("checks global api configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=secret1",
        headers = { Host = "global1.com" }
      })
      assert.res_status(200, res)
      assert.equal("1", res.headers["x-ratelimit-limit-hour"])
    end)

    it("checks api specific configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=secret1",
        headers = { Host = "api1.com" }
      })
      assert.res_status(200, res)
      assert.equal("2", res.headers["x-ratelimit-limit-hour"])
    end)

    it("checks global consumer configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=secret2",
        headers = { Host = "global1.com" }
      })
      assert.res_status(200, res)
      assert.equal("3", res.headers["x-ratelimit-limit-hour"])
    end)

    it("checks consumer specific configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=secret2",
        headers = { Host = "api2.com" }
      })
      assert.res_status(200, res)
      assert.equal("4", res.headers["x-ratelimit-limit-hour"])
    end)

    it("checks anonymous consumer specific configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = { Host = "api3.com" }
      })
      assert.res_status(200, res)
      assert.equal("5", res.headers["x-ratelimit-limit-hour"])
    end)

    describe("short-circuited requests", function()
      local FILE_LOG_PATH = os.tmpname()

      setup(function()
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong()
        dao:truncate_tables()

        do
          local service = assert(bp.services:insert {
            name = "example",
            host = helpers.mock_upstream_host,
            port = helpers.mock_upstream_port,
          })

          local route = assert(db.routes:insert {
            hosts     = { "mock_upstream" },
            protocols = { "http" },
            service   = service,
          })

          -- plugin able to short-circuit a request
          assert(dao.plugins:insert {
            name   = "key-auth",
            route_id = route.id,
          })

          -- response/body filter plugin
          assert(dao.plugins:insert {
            name   = "dummy",
            route_id = route.id,
            config = {
              append_body = "appended from body filtering",
            }
          })

          -- log phase plugin
          assert(dao.plugins:insert {
            name = "file-log",
            route_id = route.id,
            config = {
              path = FILE_LOG_PATH,
            },
          })
        end

        do
          local service = bp.services:insert {
            name = "example_err",
            host = helpers.mock_upstream_host,
            port = helpers.mock_upstream_port,
          }

          -- route that will produce an error
          local route = assert(db.routes:insert {
            hosts = { "mock_upstream_err" },
            protocols = { "http" },
            service = service,
          })

          -- plugin that produces an error
          assert(dao.plugins:insert {
            name = "dummy",
            route_id = route.id,
            config = {
              append_body = "obtained even with error",
            }
          })

          -- log phase plugin
          assert(dao.plugins:insert {
            name = "file-log",
            route_id = route.id,
            config = {
              path = FILE_LOG_PATH,
            },
          })
        end

        assert(helpers.start_kong {
          database = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        })

        proxy_client = helpers.proxy_client()
      end)

      teardown(function()
        if proxy_client then
          proxy_client:close()
        end

        os.remove(FILE_LOG_PATH)

        helpers.stop_kong()
      end)

      after_each(function()
        os.execute("echo '' > " .. FILE_LOG_PATH)
      end)

      it("execute a log plugin", function()
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "mock_upstream",
            ["X-UUID"] = uuid,
            -- /!\ no key credential
          }
        })
        assert.res_status(401, res)

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 3)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("127.0.0.1", log_message.client_ip)
        assert.equal(uuid, log_message.request.headers["x-uuid"])
      end)

      it("execute a header_filter plugin", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "mock_upstream",
          }
        })
        assert.res_status(401, res)

        -- TEST: ensure that the dummy plugin was executed by checking
        -- that headers have been injected in the header_filter phase
        -- Plugins such as CORS need to run on short-circuited requests
        -- as well.

        assert.not_nil(res.headers["dummy-plugin"])
      end)

      it("execute a body_filter plugin", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "mock_upstream",
          }
        })
        local body = assert.res_status(401, res)

        -- TEST: ensure that the dummy plugin was executed by checking
        -- that the body filtering phase has run

        assert.matches("appended from body filtering", body, nil, true)
      end)

      -- regression test for bug spotted in 0.12.0rc2
      it("responses.send stops plugin but runloop continues", function()
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200?send_error=1",
          headers = {
            ["Host"] = "mock_upstream_err",
            ["X-UUID"] = uuid,
          }
        })
        local body = assert.res_status(404, res)

        -- TEST: ensure that the dummy plugin stopped running after
        -- running responses.send

        assert.not_equal("dummy", res.headers["dummy-plugin-access-header"])

        -- ...but ensure that further phases are still executed

        -- header_filter phase of same plugin
        assert.matches("obtained even with error", body, nil, true)

        -- access phase got a chance to inject the logging plugin
        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 3)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("127.0.0.1", log_message.client_ip)
        assert.equal(uuid, log_message.request.headers["x-uuid"])
      end)
    end)

    describe("anonymous reports execution", function()
      -- anonymous reports are implemented as a plugin which is being executed
      -- by the plugins runloop, but which doesn't have a schema
      --
      -- This is a regression test after:
      --     https://github.com/Kong/kong/issues/2756
      -- to ensure that this plugin plays well when it is being executed by
      -- the runloop (which accesses plugins schemas and is vulnerable to
      -- Lua indexing errors)
      --
      -- At the time of this test, the issue only arises when a request is
      -- authenticated via an auth plugin, and the runloop runs again, and
      -- tries to evaluate is the `schema.no_consumer` flag is set.
      -- Since the reports plugin has no `schema`, this indexing fails.

      setup(function()
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong()

        assert(db:truncate())
        dao:truncate_tables()

        local service = bp.services:insert {
          name = "example",
        }

        local route = bp.routes:insert {
          hosts     = { "mock_upstream" },
          protocols = { "http" },
          service   = service,
        }

        bp.plugins:insert {
          name       = "key-auth",
          route_id   = route.id,
          service_id = service.id,
        }

        local consumer = bp.consumers:insert {
          username = "bob",
        }

        bp.keyauth_credentials:insert {
          key         = "abcd",
          consumer_id = consumer.id,
        }

        assert(helpers.start_kong {
          database          = strategy,
          nginx_conf        = "spec/fixtures/custom_nginx.template",
          anonymous_reports = true,
        })

        proxy_client = helpers.proxy_client()
      end)

      teardown(function()
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong()
      end)

      it("runs without causing an internal error", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "mock_upstream",
          },
        })
        assert.res_status(401, res)

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]   = "mock_upstream",
            ["apikey"] = "abcd",
          },
        })
        assert.res_status(200, res)
      end)
    end)

    describe("proxy-intercepted error", function()
      local FILE_LOG_PATH = os.tmpname()


      setup(function()
        assert(db:truncate())
        dao:truncate_tables()

        do
          -- service to mock HTTP 502
          local mock_service = bp.services:insert {
            name = "conn_refused",
            host = "127.0.0.2",
            port = 26865,
          }

          bp.routes:insert {
            hosts     = { "refused" },
            protocols = { "http" },
            service   = mock_service,
          }

          bp.plugins:insert {
            name = "file-log",
            service_id = mock_service.id,
            config = {
              path = FILE_LOG_PATH,
              reopen = true,
            }
          }
        end

        do
          -- service to mock HTTP 503
          local mock_service = bp.services:insert {
            name = "unavailable",
          }

          bp.routes:insert {
            hosts     = { "unavailable" },
            protocols = { "http" },
            service   = mock_service,
          }

          bp.plugins:insert {
            name = "file-log",
            service_id = mock_service.id,
            config = {
              path = FILE_LOG_PATH,
              reopen = true,
            }
          }
        end

        do
          -- service to mock HTTP 504
          local httpbin_service = bp.services:insert {
            name            = "timeout",
            host            = "httpbin.org",
            connect_timeout = 1, -- ms
          }

          bp.routes:insert {
            hosts     = { "connect_timeout" },
            protocols = { "http" },
            service   = httpbin_service,
          }

          bp.plugins:insert {
            name = "file-log",
            service_id = httpbin_service.id,
            config = {
              path = FILE_LOG_PATH,
              reopen = true,
            }
          }
        end

        do
          -- global plugin to catch Nginx-produced client errors
          bp.plugins:insert {
            name = "file-log",
            config = {
              path = FILE_LOG_PATH,
              reopen = true,
            }
          }

          bp.plugins:insert {
            name = "error-handler-log",
            config = {},
          }
        end

        -- start mock httpbin instance
        assert(helpers.start_kong {
          database = strategy,
          admin_listen = "127.0.0.1:9011",
          proxy_listen = "127.0.0.1:9010",
          proxy_listen_ssl = "127.0.0.1:9453",
          admin_listen_ssl = "127.0.0.1:9454",
          prefix = "servroot2",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        })

        -- start Kong instance with our services and plugins
        assert(helpers.start_kong {
          database = strategy,
          -- /!\ test with real nginx config
        })
      end)


      teardown(function()
        helpers.stop_kong("servroot2")
        helpers.stop_kong()
      end)


      before_each(function()
        proxy_client = helpers.proxy_client()
      end)


      after_each(function()
        pl_file.delete(FILE_LOG_PATH)

        if proxy_client then
          proxy_client:close()
        end
      end)


      it("executes a log plugin on Bad Gateway (HTTP 502)", function()
        -- triggers error_page directive
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "refused",
            ["X-UUID"] = uuid,
          }
        })
        assert.res_status(502, res) -- Bad Gateway

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 3)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("127.0.0.1", log_message.client_ip)
        assert.equal(uuid, log_message.request.headers["x-uuid"])
      end)


      pending("log plugins sees same request in error_page handler (HTTP 502)", function()
        -- PENDING: waiting on Nginx error_patch_preserve_method patch

        -- triggers error_page directive
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "POST",
          path = "/status/200?foo=bar",
          headers = {
            ["Host"] = "refused",
            ["X-UUID"] = uuid,
          },
          --[[ file-log plugin does not log request body
          body = {
            hello = "world",
          }
          --]]
        })
        assert.res_status(502, res) -- Bad Gateway

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 3)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal(uuid, log_message.request.headers["x-uuid"])
        assert.equal("refused", log_message.request.headers.host)
        assert.equal("POST", log_message.request.method)
        assert.equal("bar", log_message.request.querystring.foo)
        assert.equal("/status/200?foo=bar", log_message.upstream_uri)
      end)


      it("executes a log plugin on Service Unavailable (HTTP 503)", function()
        -- Does not trigger error_page directive (no proxy_intercept_errors)
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/503",
          headers = {
            ["Host"] = "unavailable",
            ["X-UUID"] = uuid,
          }
        })
        assert.res_status(503, res) -- Service Unavailable

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 3)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("127.0.0.1", log_message.client_ip)
        assert.equal(uuid, log_message.request.headers["x-uuid"])
      end)


      it("executes a log plugin on Gateway Timeout (HTTP 504)", function()
        -- triggers error_page directive
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "connect_timeout",
            ["X-UUID"] = uuid,
          }
        })
        assert.res_status(504, res) -- Gateway Timeout

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 3)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("127.0.0.1", log_message.client_ip)
        assert.equal(uuid, log_message.request.headers["x-uuid"])
      end)


      pending("log plugins sees same request in error_page handler (HTTP 504)", function()
        -- triggers error_page directive
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "POST",
          path = "/status/200?foo=bar",
          headers = {
            ["Host"] = "connect_timeout",
            ["X-UUID"] = uuid,
          },
          --[[ file-log plugin does not log request body
          body = {
            hello = "world",
          }
          --]]
        })
        assert.res_status(504, res) -- Gateway Timeout

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 3)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal(uuid, log_message.request.headers["x-uuid"])
        assert.equal("connect_timeout", log_message.request.headers.host)
        assert.equal("POST", log_message.request.method)
        assert.equal("bar", log_message.request.querystring.foo)
        assert.equal("/status/200?foo=bar", log_message.upstream_uri)
      end)


      it("executes a global log plugin on Nginx-produced client errors (HTTP 494)", function()
        -- triggers error_page directive
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "unavailable",
            ["X-Large"] = string.rep("a", 2^10 * 10), -- default large_client_header_buffers is 8k
            ["X-UUID"] = uuid,
          }
        })
        assert.res_status(494, res)

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 10)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))

        assert.equal(uuid, log_message.request.headers["x-uuid"])
        assert.equal(494, log_message.response.status)
      end)


      pending("log plugins sees same request in error_page handler (HTTP 494)", function()
        -- PENDING: waiting on Nginx error_patch_preserve_method patch

        -- triggers error_page directive
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "POST",
          path = "/status/200?foo=bar",
          headers = {
            ["Host"] = "unavailable",
            ["X-Large"] = string.rep("a", 2^10 * 10), -- default large_client_header_buffers is 8k
            ["X-UUID"] = uuid,
          },
          --[[ file-log plugin does not log request body
          body = {
            hello = "world",
          }
          --]]
        })
        assert.res_status(494, res)

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 10)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("POST", log_message.request.method)
        assert.equal("bar", log_message.request.querystring.foo)
        assert.equal("/status/200?foo=bar", log_message.upstream_uri)
        assert.equal(uuid, log_message.request.headers["x-uuid"])
        assert.equal("unavailable", log_message.request.headers.host)
      end)


      it("executes a global log plugin on Nginx-produced client errors (HTTP 414)", function()
        -- triggers error_page directive
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/?foo=" .. string.rep("a", 2^10 * 10),
          headers = {
            ["Host"] = "unavailable",
            ["X-UUID"] = uuid,
          }
        })
        assert.res_status(414, res)

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 10)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))

        assert.same({}, log_message.request.headers)
        assert.equal(414, log_message.response.status)
      end)


      pending("log plugins sees same request in error_page handler (HTTP 414)", function()
        -- PENDING: waiting on Nginx error_patch_preserve_method patch

        -- triggers error_page directive
        local uuid = utils.uuid()

        local res = assert(proxy_client:send {
          method = "POST",
          path = "/?foo=" .. string.rep("a", 2^10 * 10),
          headers = {
            ["Host"] = "unavailable",
            ["X-UUID"] = uuid,
          },
          --[[ file-log plugin does not log request body
          body = {
            hello = "world",
          }
          --]]
        })
        assert.res_status(414, res)

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH)
                 and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 10)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        local ins = require "inspect"
        print(ins(log_message))
        assert.equal("POST", log_message.request.method)
        assert.equal("", log_message.upstream_uri) -- no URI here since Nginx could not parse request
        assert.is_nil(log_message.request.headers["x-uuid"]) -- none since Nginx could not parse request
        assert.is_nil(log_message.request.headers.host) -- none as well
      end)


      it("executes plugins header_filter/body_filter on Nginx-produced client errors (HTTP 4xx)", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/?foo=" .. string.rep("a", 2^10 * 10),
          headers = {
            ["Host"] = "unavailable",
          }
        })
        local body = assert.res_status(414, res)
        assert.equal("header_filter", res.headers["Log-Plugin-Phases"])
        assert.equal("body_filter", body)
      end)


      it("executes plugins header_filter/body_filter on Nginx-produced server errors (HTTP 5xx)", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "connect_timeout",
          }
        })
        local body = assert.res_status(504, res) -- Gateway Timeout
        assert.equal("rewrite,access,header_filter", res.headers["Log-Plugin-Phases"]) -- rewrite + acecss from original request handling
        assert.equal("body_filter", body)
      end)


      it("sees ctx introspection variables on Nginx-produced server errors (HTTP 5xx)", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "connect_timeout",
          }
        })
        assert.res_status(504, res) -- Gateway Timeout
        assert.equal("timeout", res.headers["Log-Plugin-Service-Matched"])
      end)
    end)
  end)
end
