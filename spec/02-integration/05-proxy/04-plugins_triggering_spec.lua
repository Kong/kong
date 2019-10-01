local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"


local LOG_WAIT_TIMEOUT = 10


for _, strategy in helpers.each_strategy() do

  describe("Plugins triggering [#" .. strategy .. "]", function()
    local proxy_client
    local db
    local bp

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "apis",
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      }, {
        "error-handler-log",
        "short-circuit",
        "short-circuit-last",
        "error-generator",
      })

      db:truncate("ratelimiting_metrics")

      local consumer1 = bp.consumers:insert {
        username = "consumer1"
      }

      bp.keyauth_credentials:insert {
        key      = "secret1",
        consumer = { id = consumer1.id },
      }

      local consumer2 = bp.consumers:insert {
        username = "consumer2"
      }

      bp.keyauth_credentials:insert {
        key      = "secret2",
        consumer = { id = consumer2.id },
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
          policy = "local",
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
        name    = "rate-limiting",
        route   = { id = route1.id },
        service = { id = service2.id },
        config  = {
          policy = "local",
          hour  = 2,
        },
      }

      -- Consumer Specific Configuration
      bp.plugins:insert {
        name     = "rate-limiting",
        consumer = { id = consumer2.id },
        config   = {
          policy = "local",
          hour   = 3,
        },
      }

      -- API and Consumer Configuration
      local service3 = bp.services:insert {
        name = "api2",
      }

      local route2 = bp.routes:insert {
        hosts     = { "api2.com" },
        protocols = { "http" },
        service   = service3,
      }

      bp.plugins:insert {
        name     = "rate-limiting",
        route    = { id = route2.id },
        consumer = { id = consumer2.id },
        config   = {
          policy = "local",
          hour   = 4,
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
        route       = { id = route3.id },
        service     = { id = service4.id },
      }

      bp.plugins:insert {
        name     = "rate-limiting",
        route    = { id = route3.id },
        service  = { id = service4.id },
        consumer = { id = consumer3.id },
        config   = {
          policy = "local",
          hour   = 5,
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then proxy_client:close() end
      helpers.stop_kong(nil, true)
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

      lazy_setup(function()
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong(nil, true)
        db:truncate("routes")
        db:truncate("services")
        db:truncate("consumers")
        db:truncate("plugins")
        db:truncate("keyauth_credentials")

        do
          local service = bp.services:insert {
            name = "example",
            host = helpers.mock_upstream_host,
            port = helpers.mock_upstream_port,
          }

          local route = assert(bp.routes:insert {
            hosts     = { "mock_upstream" },
            protocols = { "http" },
            service   = service,
          })

          -- plugin able to short-circuit a request
          assert(bp.plugins:insert {
            name  = "key-auth",
            route = { id = route.id },
          })

          -- response/body filter plugin
          assert(bp.plugins:insert {
            name   = "dummy",
            route  = { id = route.id },
            config = {
              append_body = "appended from body filtering",
            }
          })

          -- log phase plugin
          assert(bp.plugins:insert {
            name   = "file-log",
            route  = { id = route.id },
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
          local route = assert(bp.routes:insert {
            hosts = { "mock_upstream_err" },
            protocols = { "http" },
            service = service,
          })

          -- plugin that produces an error
          assert(bp.plugins:insert {
            name   = "dummy",
            route  = { id = route.id },
            config = {
              append_body = "obtained even with error",
            }
          })

          -- log phase plugin
          assert(bp.plugins:insert {
            name   = "file-log",
            route  = { id = route.id },
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

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end

        os.remove(FILE_LOG_PATH)

        helpers.stop_kong(nil, true)
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
        end, LOG_WAIT_TIMEOUT)

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
        end, LOG_WAIT_TIMEOUT)

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

      lazy_setup(function()
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong(nil, true)

        db:truncate("routes")
        db:truncate("services")
        db:truncate("consumers")
        db:truncate("plugins")
        db:truncate("keyauth_credentials")

        local service = bp.services:insert {
          name = "example",
        }

        local route = bp.routes:insert {
          hosts     = { "mock_upstream" },
          protocols = { "http" },
          service   = service,
        }

        bp.plugins:insert {
          name    = "key-auth",
          route   = { id = route.id },
          service = { id = service.id },
        }

        local consumer = bp.consumers:insert {
          username = "bob",
        }

        bp.keyauth_credentials:insert {
          key      = "abcd",
          consumer = { id = consumer.id },
        }

        assert(helpers.start_kong {
          database          = strategy,
          nginx_conf        = "spec/fixtures/custom_nginx.template",
          --anonymous_reports = true,
        })

        proxy_client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong(nil, true)
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


      lazy_setup(function()
        db:truncate("routes")
        db:truncate("services")
        db:truncate("consumers")
        db:truncate("plugins")
        db:truncate("keyauth_credentials")

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
            name     = "file-log",
            service  = { id = mock_service.id },
            config   = {
              path   = FILE_LOG_PATH,
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
            name     = "file-log",
            service  = { id = mock_service.id },
            config   = {
              path   = FILE_LOG_PATH,
              reopen = true,
            }
          }
        end

        do
          -- service to mock HTTP 504
          local blackhole_service = bp.services:insert {
            name            = "timeout",
            host            = helpers.blackhole_host,
            connect_timeout = 1, -- ms
          }

          bp.routes:insert {
            hosts     = { "connect_timeout" },
            protocols = { "http" },
            service   = blackhole_service,
          }

          bp.plugins:insert {
            name     = "file-log",
            service  = { id = blackhole_service.id },
            config   = {
              path   = FILE_LOG_PATH,
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

        -- start Kong instance with our services and plugins
        assert(helpers.start_kong {
          database = strategy,
          -- /!\ test with real nginx config
        })

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
      end)


      lazy_teardown(function()
        helpers.stop_kong("servroot2")
        helpers.stop_kong(nil, true)
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
        end, LOG_WAIT_TIMEOUT)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("127.0.0.1", log_message.client_ip)
        assert.equal(uuid, log_message.request.headers["x-uuid"])
      end)


      it("log plugins sees same request in error_page handler (HTTP 502)", function()
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
        end, LOG_WAIT_TIMEOUT)

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
        end, LOG_WAIT_TIMEOUT)

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
        end, LOG_WAIT_TIMEOUT)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("127.0.0.1", log_message.client_ip)
        assert.equal(uuid, log_message.request.headers["x-uuid"])
      end)


      it("log plugins sees same request in error_page handler (HTTP 504)", function()
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
        end, LOG_WAIT_TIMEOUT)

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
        end, LOG_WAIT_TIMEOUT)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))

        assert.equal(uuid, log_message.request.headers["x-uuid"])
        assert.equal(494, log_message.response.status)
      end)


      it("log plugins sees same request in error_page handler (HTTP 494)", function()
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
        end, LOG_WAIT_TIMEOUT)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
        assert.equal("POST", log_message.request.method)
        assert.equal("bar", log_message.request.querystring.foo)
        assert.equal("", log_message.upstream_uri) -- no URI here since Nginx could not parse request
        assert.equal(uuid, log_message.request.headers["x-uuid"])
        assert.is_nil(log_message.request.headers.host) -- none as well
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
        end, LOG_WAIT_TIMEOUT)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))

        assert.same({}, log_message.request.headers)
        assert.equal(414, log_message.response.status)
      end)


      it("log plugins sees same request in error_page handler (HTTP 414)", function()
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
        end, LOG_WAIT_TIMEOUT)

        local log = pl_file.read(FILE_LOG_PATH)
        local log_message = cjson.decode(pl_stringx.strip(log))
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

    describe("plugin with run_on", function()
      describe("#http", function()
        local proxy_ssl_client

        lazy_setup(function()
          if proxy_client then
            proxy_client:close()
          end

          helpers.stop_kong()

          db:truncate("routes")
          db:truncate("services")
          db:truncate("plugins")

          do
            if strategy == "off" then
              assert(bp.cluster_ca:insert())
            end

            -- never used as the plugins short-circuit
            local mock_service = assert(bp.services:insert {
              name = "mock-service",
              host = helpers.mock_upstream_host,
              port = helpers.mock_upstream_port,
            })

            local receiving_sidecar = assert(bp.services:insert {
              name = "receiving-sidecar",
              host = helpers.mock_upstream_host,
              port = 18443,
              path = "/status/200",
              protocol = "https",
            })

            --

            local first_on_first = assert(bp.routes:insert {
              hosts     = { "first-on-first.org" },
              protocols = { "http" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_first.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = first_on_first.id },
              config = {
                status = 503,
                message = "first-on-first"
              },
              run_on = "first",
            }

            --

            local first_on_first_https = assert(bp.routes:insert {
              hosts     = { "first-on-first-https.org" },
              protocols = { "https" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_first_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = first_on_first_https.id },
              config = {
                status = 503,
                message = "first-on-first-https"
              },
              run_on = "first",
            }

            --

            local first_on_second_a = assert(bp.routes:insert {
              hosts     = { "first-on-second.org" },
              protocols = { "http" },
              service   = receiving_sidecar,
            })

            local first_on_second_b = assert(bp.routes:insert {
              hosts      = { "first-on-second.org" },
              protocols  = { "https" },
              paths      = { "/status/200" },
              strip_path = false,
              service    = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_second_a.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_second_b.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = first_on_second_b.id },
              config = {
                status = 503,
                message = "first-on-second"
              },
              run_on = "all",
            }

            --

            local first_on_second_a_https = assert(bp.routes:insert {
              hosts     = { "first-on-second-https.org" },
              protocols = { "https" },
              service   = receiving_sidecar,
            })

            local first_on_second_b_https = assert(bp.routes:insert {
              hosts      = { "first-on-second-https.org" },
              protocols  = { "https" },
              paths      = { "/status/200" },
              strip_path = false,
              service    = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_second_a_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_second_b_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = first_on_second_b_https.id },
              config = {
                status = 503,
                message = "first-on-second"
              },
              run_on = "all",
            }

            --

            local second_on_second_a = assert(bp.routes:insert {
              hosts     = { "second-on-second.org" },
              protocols = { "http" },
              service   = receiving_sidecar,
            })

            local second_on_second_b = assert(bp.routes:insert {
              hosts      = { "second-on-second.org" },
              protocols  = { "https" },
              paths      = { "/status/200" },
              strip_path = false,
              service    = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_second_a.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_second_b.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = second_on_second_b.id },
              config = {
                status = 503,
                message = "second-on-second"
              },
              run_on = "second",
            }

            --

            local second_on_second_a_https = assert(bp.routes:insert {
              hosts     = { "second-on-second-https.org" },
              protocols = { "https" },
              service   = receiving_sidecar,
            })

            local second_on_second_b_https = assert(bp.routes:insert {
              hosts      = { "second-on-second-https.org" },
              protocols  = { "https" },
              paths      = { "/status/200" },
              strip_path = false,
              service    = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_second_a_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_second_b_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = second_on_second_b_https.id },
              config = {
                status = 503,
                message = "second-on-second-https"
              },
              run_on = "second",
            }

            --

            local second_on_first = assert(bp.routes:insert {
              hosts     = { "second-on-first.org" },
              protocols = { "http" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_first.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = second_on_first.id },
              config = {
                status = 503,
                message = "second-on-first"
              },
              run_on = "all",
            }

            --

            local second_on_first_https = assert(bp.routes:insert {
              hosts     = { "second-on-first-https.org" },
              protocols = { "https" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_first_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = second_on_first_https.id },
              config = {
                status = 503,
                message = "second-on-first-https"
              },
              run_on = "all",
            }

            --

            local all_on_first = assert(bp.routes:insert {
              hosts     = { "all-on-first.org" },
              protocols = { "http" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = all_on_first.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_first.id },
              config = {
                status = 503,
                message = "all-on-first"
              },
              run_on = "all",
            }

            --

            local all_on_first_https = assert(bp.routes:insert {
              hosts     = { "all-on-first-https.org" },
              protocols = { "https" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = all_on_first_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_first_https.id },
              config = {
                status = 503,
                message = "all-on-first-https"
              },
              run_on = "all",
            }

            --

            local all_on_second_a = assert(bp.routes:insert {
              hosts     = { "all-on-second.org" },
              protocols = { "http" },
              service   = receiving_sidecar,
            })

            local all_on_second_b = assert(bp.routes:insert {
              hosts      = { "all-on-second.org" },
              protocols  = { "https" },
              paths      = { "/status/200" },
              strip_path = false,
              service    = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_second_a.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_second_b.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = all_on_second_b.id },
              config = {
                status = 503,
                message = "all-on-second"
              },
              run_on = "all",
            }

            --

            local all_on_second_a_https = assert(bp.routes:insert {
              hosts     = { "all-on-second-https.org" },
              protocols = { "http" },
              service   = receiving_sidecar,
            })

            local all_on_second_b_https = assert(bp.routes:insert {
              hosts      = { "all-on-second-https.org" },
              protocols  = { "https" },
              paths      = { "/status/200" },
              strip_path = false,
              service    = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_second_a_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_second_b_https.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = all_on_second_b_https.id },
              config = {
                status = 503,
                message = "all-on-second-https"
              },
              run_on = "all",
            }
          end

          assert(helpers.start_kong {
            prefix       = "servroot1",
            database     = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          })

          assert(helpers.start_kong {
            prefix       = "servroot2",
            database     = strategy,
            proxy_listen = "0.0.0.0:18000, 0.0.0.0:18443 ssl",
            admin_listen = "off",
          })

          proxy_client = helpers.proxy_client()
          proxy_ssl_client = helpers.proxy_ssl_client()
        end)

        lazy_teardown(function()
          if proxy_client then
            proxy_client:close()
          end

          if proxy_ssl_client then
            proxy_ssl_client:close()
          end

          helpers.stop_kong("servroot1", true)
          helpers.stop_kong("servroot2", true)
        end)

        it("= 'first' does get executed when running on first", function()
          local res = assert(proxy_client:get("/status/200", {
            headers = {
              ["Host"] = "first-on-first.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "first-on-first"
          }, json)
        end)

        it("= 'first' does get executed when running on first (https)", function()
          local res = assert(proxy_ssl_client:get("/status/200", {
            headers = {
              ["Host"] = "first-on-first-https.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "first-on-first-https"
          }, json)
        end)

        it("= 'first' does not get executed when running on second", function()
          local res = assert(proxy_client:get("/", {
            headers = {
              ["Host"] = "first-on-second.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "first-on-second"
          }, json)
        end)

        it("= 'first' does not get executed when running on second (https)", function()
          local res = assert(proxy_ssl_client:get("/", {
            headers = {
              ["Host"] = "first-on-second-https.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "first-on-second"
          }, json)
        end)

        it("= 'second' does get executed when running on second", function()
          local res = assert(proxy_client:get("/", {
            headers = {
              ["Host"] = "second-on-second.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "second-on-second"
          }, json)
        end)

        it("= 'second' does get executed when running on second (https)", function()
          local res = assert(proxy_ssl_client:get("/", {
            headers = {
              ["Host"] = "second-on-second-https.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "second-on-second-https"
          }, json)
        end)

        it("= 'second' does not get executed when running on first", function()
          local res = assert(proxy_client:get("/status/200", {
            headers = {
              ["Host"] = "second-on-first.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "second-on-first"
          }, json)
        end)

        it("= 'second' does not get executed when running on first (https)", function()
          local res = assert(proxy_ssl_client:get("/status/200", {
            headers = {
              ["Host"] = "second-on-first-https.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "second-on-first-https"
          }, json)
        end)

        it("= 'all' does get executed when running on first", function()
          local res = assert(proxy_client:get("/status/200", {
            headers = {
              ["Host"] = "all-on-first.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "all-on-first"
          }, json)
        end)

        it("= 'all' does get executed when running on first (https)", function()
          local res = assert(proxy_ssl_client:get("/status/200", {
            headers = {
              ["Host"] = "all-on-first-https.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "all-on-first-https"
          }, json)
        end)

        it("= 'all' does get executed when running on second", function()
          local res = assert(proxy_client:get("/", {
            headers = {
              ["Host"] = "all-on-second.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "all-on-second"
          }, json)
        end)

        it("= 'all' does get executed when running on second (https)", function()
          local res = assert(proxy_ssl_client:get("/", {
            headers = {
              ["Host"] = "all-on-second-https.org",
            }
          }))

          local body = assert.res_status(503, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "all-on-second-https"
          }, json)
        end)
      end)

      describe("#stream", function()
        lazy_setup(function()
          helpers.stop_kong()

          db:truncate("routes")
          db:truncate("services")
          db:truncate("plugins")

          do
            if strategy == "off" then
              assert(bp.cluster_ca:insert())
            end

            -- never used as the plugins short-circuit
            local mock_service = assert(bp.services:insert {
              name = "mock-service",
              protocol = "tcp",
              host = helpers.mock_upstream_host,
              port = helpers.mock_upstream_port,
            })

            --

            local first_on_first = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18003
                }
              },
              protocols = { "tcp" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_first.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = first_on_first.id },
              config = {
                status = 503,
                message = "first-on-first"
              },
              run_on = "first",
            }

            --

            local first_on_first_tls = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18443
                }
              },
              protocols = { "tls" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_first_tls.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = first_on_first_tls.id },
              config = {
                status = 503,
                message = "first-on-first-tls"
              },
              run_on = "first",
            }

            --

            local receiving_sidecar_a = assert(bp.services:insert {
              name = "receiving-sidecar-a",
              host = helpers.mock_upstream_host,
              port = 19444,
              protocol = "tls",
            })

            local first_on_second_a = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18004
                }
              },
              protocols = { "tcp" },
              service   = receiving_sidecar_a,
            })

            local first_on_second_b = assert(bp.routes:insert {
              destinations = {
                {
                  port = 19444
                }
              },
              protocols = { "tls" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_second_a.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_second_b.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = first_on_second_b.id },
              config = {
                status = 503,
                message = "first-on-second"
              },
              run_on = "all",
            }

            --

            local first_on_second_tls = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18444
                }
              },
              protocols = { "tls" },
              service   = receiving_sidecar_a,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = first_on_second_tls.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            --

            local receiving_sidecar_b = assert(bp.services:insert {
              name = "receiving-sidecar-b",
              host = helpers.mock_upstream_host,
              port = 19445,
              protocol = "tls",
            })

            local second_on_second_a = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18005
                }
              },
              protocols = { "tcp" },
              service   = receiving_sidecar_b,
            })

            local second_on_second_b = assert(bp.routes:insert {
              destinations = {
                {
                  port = 19445
                }
              },
              protocols = { "tls" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_second_a.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_second_b.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = second_on_second_b.id },
              config = {
                status = 503,
                message = "second-on-second"
              },
              run_on = "second",
            }

            --

            local second_on_second_tls = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18445
                }
              },
              protocols = { "tls" },
              service   = receiving_sidecar_b,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_second_tls.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            --

            local second_on_first = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18006
                }
              },
              protocols = { "tcp" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_first.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = second_on_first.id },
              config = {
                status = 503,
                message = "second-on-first"
              },
              run_on = "all",
            }

            --

            local second_on_first_tls = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18446
                }
              },
              protocols = { "tls" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = second_on_first_tls.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = second_on_first_tls.id },
              config = {
                status = 503,
                message = "second-on-first-tls"
              },
              run_on = "all",
            }

            --

            local all_on_first = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18007
                }
              },
              protocols = { "tcp" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_first.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = all_on_first.id },
              config = {
                status = 503,
                message = "all-on-first"
              },
              run_on = "all",
            }

            --

            local all_on_first = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18447
                }
              },
              protocols = { "tls" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_first.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = all_on_first.id },
              config = {
                status = 503,
                message = "all-on-first-tls"
              },
              run_on = "all",
            }

            --

            local receiving_sidecar_c = assert(bp.services:insert {
              name = "receiving-sidecar-c",
              host = helpers.mock_upstream_host,
              port = 19448,
              protocol = "tls",
            })

            local all_on_second_a = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18008
                }
              },
              protocols = { "tcp" },
              service   = receiving_sidecar_c,
            })

            local all_on_second_b = assert(bp.routes:insert {
              destinations = {
                {
                  port = 19448
                }
              },
              protocols = { "tls" },
              service   = mock_service,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_second_a.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_second_b.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "first",
            }

            bp.plugins:insert {
              name = "short-circuit-last",
              route = { id = all_on_second_b.id },
              config = {
                status = 503,
                message = "all-on-second"
              },
              run_on = "all",
            }

            --

            local all_on_second_tls = assert(bp.routes:insert {
              destinations = {
                {
                  port = 18448
                }
              },
              protocols = { "tls" },
              service   = receiving_sidecar_c,
            })

            bp.plugins:insert {
              name = "short-circuit",
              route = { id = all_on_second_tls.id },
              config = {
                status = 500,
                message = "should not be executed"
              },
              run_on = "second",
            }
          end

          assert(helpers.start_kong {
            prefix        = "servroot1",
            database      = strategy,
            stream_listen = "0.0.0.0:18003,0.0.0.0:18443,0.0.0.0:18004,0.0.0.0:18444," ..
                            "0.0.0.0:18005,0.0.0.0:18445,0.0.0.0:18006,0.0.0.0:18446," ..
                            "0.0.0.0:18007,0.0.0.0:18447,0.0.0.0:18008,0.0.0.0:18448",
            proxy_listen  = "off",
            admin_listen  = "off",
          })

          assert(helpers.start_kong {
            prefix        = "servroot2",
            database      = strategy,
            stream_listen = "0.0.0.0:19444,0.0.0.0:19445,0.0.0.0:19448",
            proxy_listen  = "off",
            admin_listen  = "off",
          })
        end)

        lazy_teardown(function()
          helpers.stop_kong("servroot1", true)
          helpers.stop_kong("servroot2", true)
        end)

        it("= 'first' does get executed when running on first", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18003))

          -- TODO: we need to get rid of the next line!
          assert(tcp:send("this is just for the stream preread as it needs some data or otherwise it just hangs."))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "first-on-first"
          }, json)
        end)

        it("= 'first' does get executed when running on first (tls)", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18443))

          -- TODO: should SNI really be mandatory?
          assert(tcp:sslhandshake(false, "first-on-first.org"))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "first-on-first-tls"
          }, json)
        end)

        it("= 'first' does not get executed when running on second", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18004))

          -- TODO: we need to get rid of the next line!
          assert(tcp:send("this is just for the stream preread as it needs some data or otherwise it just hangs."))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "first-on-second"
          }, json)
        end)

        it("= 'first' does not get executed when running on second (tls)", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18444))

          -- TODO: should SNI really be mandatory?
          assert(tcp:sslhandshake(false, "first-on-second.org"))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "first-on-second"
          }, json)
        end)

        it("= 'second' does get executed when running on second", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18005))

          -- TODO: we need to get rid of the next line!
          assert(tcp:send("this is just for the stream preread as it needs some data or otherwise it just hangs."))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "second-on-second"
          }, json)
        end)

        it("= 'second' does get executed when running on second (tls)", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18445))

          -- TODO: should SNI really be mandatory?
          assert(tcp:sslhandshake(false, "second-on-second.org"))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "second-on-second"
          }, json)
        end)

        it("= 'second' does not get executed when running on first", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18006))

          --TODO: we need to get rid of the next line!
          assert(tcp:send("this is just for the stream preread as it needs some data or otherwise it just hangs."))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "second-on-first"
          }, json)
        end)

        it("= 'second' does not get executed when running on first (tls)", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18446))

          -- TODO: should SNI really be mandatory?
          assert(tcp:sslhandshake(false, "second-on-first.org"))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "second-on-first-tls"
          }, json)
        end)

        it("= 'all' does get executed when running on first", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18007))

          -- TODO: we need to get rid of the next line!
          assert(tcp:send("this is just for the stream preread as it needs some data or otherwise it just hangs."))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "all-on-first"
          }, json)
        end)

        it("= 'all' does get executed when running on first (tls)", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18447))

          -- TODO: should SNI really be mandatory?
          assert(tcp:sslhandshake(false, "all-on-first.org"))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "all-on-first-tls"
          }, json)
        end)

        it("= 'all' does get executed when running on second", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18008))

          -- TODO: we need to get rid of the next line!
          assert(tcp:send("this is just for the stream preread as it needs some data or otherwise it just hangs."))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "all-on-second"
          }, json)
        end)

        it("= 'all' does get executed when running on second (tls)", function()
          local tcp = ngx.socket.tcp()
          assert(tcp:connect("127.0.0.1", 18448))

          -- TODO: should SNI really be mandatory?
          assert(tcp:sslhandshake(false, "all-on-second.org"))

          local body = assert(tcp:receive("*a"))
          local json = cjson.decode(body)

          assert.same({
            status  = 503,
            message = "all-on-second"
          }, json)
        end)
      end)
    end)

    describe("plugin's init_worker", function()
      describe("[pre-configured]", function()
        lazy_setup(function()
          if proxy_client then
            proxy_client:close()
          end

          helpers.stop_kong()

          db:truncate("routes")
          db:truncate("services")
          db:truncate("plugins")

          -- never used as the plugins short-circuit
          local service = assert(bp.services:insert {
            name = "mock-service",
            host = helpers.mock_upstream_host,
            port = helpers.mock_upstream_port,
          })

          local route = assert(bp.routes:insert {
            hosts     = { "runs-init-worker.org" },
            protocols = { "http" },
            service   = service,
          })

          bp.plugins:insert {
            name = "short-circuit",
            route = { id = route.id },
            config = {
              status = 200,
              message = "plugin executed"
            },
            run_on = "first",
          }

          assert(helpers.start_kong {
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          })

          proxy_client = helpers.proxy_client()
        end)

        lazy_teardown(function()
          if proxy_client then
            proxy_client:close()
          end

          helpers.stop_kong(nil, true)
        end)

        it("is executed", function()
          local res = assert(proxy_client:get("/status/400", {
            headers = {
              ["Host"] = "runs-init-worker.org",
            }
          }))

          assert.equal("true", res.headers["Kong-Init-Worker-Called"])

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)

          assert.same({
            status  = 200,
            message = "plugin executed"
          }, json)
        end)
      end)

      if strategy ~= "off" then
        describe("[runtime-configured]", function()
          local admin_client
          local route

          lazy_setup(function()
            if proxy_client then
              proxy_client:close()
            end

            helpers.stop_kong()

            db:truncate("routes")
            db:truncate("services")
            db:truncate("plugins")

            -- never used as the plugins short-circuit
            local service = assert(bp.services:insert {
              name = "mock-service",
              host = helpers.mock_upstream_host,
              port = helpers.mock_upstream_port,
            })

            route = assert(bp.routes:insert {
              hosts     = { "runs-init-worker.org" },
              protocols = { "http" },
              service   = service,
            })

            assert(helpers.start_kong {
              database   = strategy,
              nginx_conf = "spec/fixtures/custom_nginx.template",
            })

            proxy_client = helpers.proxy_client()
            admin_client = helpers.admin_client()
          end)

          lazy_teardown(function()
            if proxy_client then
              proxy_client:close()
            end

            if admin_client then
              admin_client:close()
            end

            helpers.stop_kong(nil, true)
          end)

          it("is executed", function()
            local res = assert(admin_client:post("/plugins", {
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = {
                name = "short-circuit",
                route = { id = route.id },
                config = {
                  status = 200,
                  message = "plugin executed"
                },
                run_on = "first",
              }
            }))

            assert.res_status(201, res)

            local res = assert(proxy_client:get("/status/400", {
              headers = {
                ["Host"] = "runs-init-worker.org",
              }
            }))

            assert.equal("true", res.headers["Kong-Init-Worker-Called"])

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same({
              status  = 200,
              message = "plugin executed"
            }, json)
          end)
        end)
      end
    end)
  end)
end
