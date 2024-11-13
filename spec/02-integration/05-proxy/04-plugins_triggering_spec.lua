local helpers = require "spec.helpers"
local uuid = require "kong.tools.uuid"
local cjson = require "cjson"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local shell = require "resty.shell"


local LOG_WAIT_TIMEOUT = 10
local TEST_CONF = helpers.test_conf


local function find_log_line(FILE_LOG_PATH, uuid, custom_check)
  if pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0 then
    local f = assert(io.open(FILE_LOG_PATH, "r"))
    local line = f:read("*line")

    while line do
      local log_message = assert(cjson.decode(line))
      if log_message.client_ip == "127.0.0.1" then
        if uuid and log_message.request.headers["x-uuid"] ~= uuid then
          goto continue
        end

        if custom_check and not custom_check(log_message) then
          goto continue
        end

        -- found
        f:close()
        return log_message
      end

      ::continue::
      line = f:read("*line")
    end

    f:close()
  end

  return false
end


local function wait_for_log_line(FILE_LOG_PATH, uuid, custom_check)
  helpers.wait_until(function()
    return find_log_line(FILE_LOG_PATH, uuid, custom_check)
  end, LOG_WAIT_TIMEOUT)
end


for _, strategy in helpers.each_strategy() do

  describe("Plugins triggering [#" .. strategy .. "]", function()
    local proxy_client
    local db
    local bp

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      }, {
        "error-handler-log",
        "short-circuit",
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
        hosts     = { "global1.test" },
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
        hosts     = { "api1.test" },
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
        hosts     = { "api2.test" },
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
        hosts     = { "api3.test" },
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

      local service_error = bp.services:insert {
        name = "service-error",
      }

      bp.routes:insert {
        hosts     = { "service-error.test" },
        protocols = { "http" },
        service   = service_error,
      }

      bp.plugins:insert {
        name     = "error-generator",
        service  = { id = service_error.id },
        config   = {
          access = true,
        }
      }

      bp.plugins:insert {
        name     = "error-handler-log",
        service  = { id = service_error.id },
        config   = {},
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then proxy_client:close() end
      helpers.stop_kong()
    end)

    it("checks global configuration without credentials", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = { Host = "global1.test" }
      })
      assert.res_status(401, res)
    end)

    it("checks global api configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=secret1",
        headers = { Host = "global1.test" }
      })
      assert.res_status(200, res)
      assert.equal("1", res.headers["x-ratelimit-limit-hour"])
    end)

    it("checks api specific configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=secret1",
        headers = { Host = "api1.test" }
      })
      assert.res_status(200, res)
      assert.equal("2", res.headers["x-ratelimit-limit-hour"])
    end)

    it("checks global consumer configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=secret2",
        headers = { Host = "global1.test" }
      })
      assert.res_status(200, res)
      assert.equal("3", res.headers["x-ratelimit-limit-hour"])
    end)

    it("checks consumer specific configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=secret2",
        headers = { Host = "api2.test" }
      })
      assert.res_status(200, res)
      assert.equal("4", res.headers["x-ratelimit-limit-hour"])
    end)

    it("checks anonymous consumer specific configuration", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = { Host = "api3.test" }
      })
      assert.res_status(200, res)
      assert.equal("5", res.headers["x-ratelimit-limit-hour"])
    end)

    it("builds complete plugins iterator even when plugin errors", function()
      local res = proxy_client:get("/status/200", {
        headers = {
          Host = "service-error.test",
        }
      })

      assert.res_status(500, res)
      assert.equal("header_filter", res.headers["Log-Plugin-Phases"])
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

      before_each(function()
        helpers.clean_logfile(FILE_LOG_PATH)
        shell.run("chmod 0777 " .. FILE_LOG_PATH, nil, 0)
      end)

      it("execute a log plugin", function()
        local uuid = uuid.uuid()

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

        wait_for_log_line(FILE_LOG_PATH, uuid)
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
        local uuid = uuid.uuid()

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
        wait_for_log_line(FILE_LOG_PATH, uuid)
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
        if proxy_client then
          proxy_client:close()
        end

        helpers.stop_kong()

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
          -- plugin to mock runtime exception
          local mock_one_fn = [[
            local nilValue = nil
            kong.log.info('test' .. nilValue)
          ]]

          local mock_two_fn = [[
            ngx.header['X-Source'] = kong.response.get_source()
          ]]

          local mock_service = bp.services:insert {
            name = "runtime_exception",
          }

          bp.routes:insert {
            hosts     = { "runtime_exception" },
            protocols = { "http" },
            service   = mock_service,
          }

          bp.plugins:insert {
            name     = "pre-function",
            service  = { id = mock_service.id },
            config  = {
              ["access"] = { mock_one_fn },
              ["header_filter"] = { mock_two_fn },
            },
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
        helpers.stop_kong()
      end)


      before_each(function()
        proxy_client = helpers.proxy_client()
        helpers.clean_logfile(FILE_LOG_PATH)
        shell.run("chmod 0777 " .. FILE_LOG_PATH, nil, 0)
      end)


      after_each(function()
        pl_file.delete(FILE_LOG_PATH)

        if proxy_client then
          proxy_client:close()
        end
      end)


      it("executes a log plugin on Bad Gateway (HTTP 502)", function()
        -- triggers error_page directive
        local uuid = uuid.uuid()

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

        wait_for_log_line(FILE_LOG_PATH, uuid)
      end)


      it("log plugins sees same request in error_page handler (HTTP 502)", function()
        -- triggers error_page directive
        local uuid = uuid.uuid()

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

        wait_for_log_line(FILE_LOG_PATH, uuid, function(log_message)
        return "refused" == log_message.request.headers.host
               and "POST" == log_message.request.method
               and "bar" == log_message.request.querystring.foo
               and "/status/200?foo=bar" == log_message.upstream_uri
        end)
      end)


      it("executes a log plugin on Service Unavailable (HTTP 503)", function()
        -- Does not trigger error_page directive (no proxy_intercept_errors)
        local uuid = uuid.uuid()

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

        wait_for_log_line(FILE_LOG_PATH, uuid)
      end)


      it("executes a log plugin on Gateway Timeout (HTTP 504)", function()
        -- triggers error_page directive
        local uuid = uuid.uuid()

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

        wait_for_log_line(FILE_LOG_PATH, uuid)
      end)


      it("log plugins sees same request in error_page handler (HTTP 504)", function()
        -- triggers error_page directive
        local uuid = uuid.uuid()

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

        wait_for_log_line(FILE_LOG_PATH, uuid, function(log_message)
          return "connect_timeout" == log_message.request.headers.host
                 and "POST" == log_message.request.method
                 and "bar" == log_message.request.querystring.foo
                 and "/status/200?foo=bar" == log_message.upstream_uri
        end)
      end)


      it("executes a global log plugin on Nginx-produced client errors (HTTP 400)", function()
        -- triggers error_page directive
        local uuid = uuid.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "unavailable",
            ["X-Large"] = string.rep("a", 2^10 * 10), -- default large_client_header_buffers is 8k
            ["X-UUID"] = uuid,
          }
        })
        assert.res_status(400, res)

        -- close and reopen to flush the request
        proxy_client:close()
        proxy_client = helpers.proxy_client()

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        wait_for_log_line(FILE_LOG_PATH, nil, function(log_message)
          return 400 == log_message.response.status
        end)
      end)


      it("log plugins sees same request in error_page handler (HTTP 400)", function()
        -- triggers error_page directive
        local uuid = uuid.uuid()

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
        assert.res_status(400, res)

        -- close and reopen to flush the request
        proxy_client:close()
        proxy_client = helpers.proxy_client()

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        wait_for_log_line(FILE_LOG_PATH, nil, function(log_message)
          return "POST" == log_message.request.method
                 and "bar" == log_message.request.querystring.foo
                 and "" == log_message.upstream_uri -- no URI here since Nginx could not parse request
        end)
      end)


      it("executes a global log plugin on Nginx-produced client errors (HTTP 414)", function()
        -- triggers error_page directive
        local uuid = uuid.uuid()

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/?foo=" .. string.rep("a", 2^10 * 10),
          headers = {
            ["Host"] = "unavailable",
            ["X-UUID"] = uuid,
          }
        })
        assert.res_status(414, res)

        -- close and reopen to flush the request
        proxy_client:close()
        proxy_client = helpers.proxy_client()

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        wait_for_log_line(FILE_LOG_PATH, nil, function(log_message)
          return #log_message.request.headers == 0
                 and 414 == log_message.response.status
        end)
      end)


      it("log plugins sees same request in error_page handler (HTTP 414)", function()
        -- triggers error_page directive
        local uuid = uuid.uuid()

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

        -- close and reopen to flush the request
        proxy_client:close()
        proxy_client = helpers.proxy_client()

        -- TEST: ensure that our logging plugin was executed and wrote
        -- something to disk.

        wait_for_log_line(FILE_LOG_PATH, nil, function(log_message)
          return "POST" == log_message.request.method
                 and "" == log_message.upstream_uri -- no URI here since Nginx could not parse request
                 and nil == log_message.request.headers["x-uuid"] -- none since Nginx could not parse request
                 and nil == log_message.request.headers.host -- none as well
        end)
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

      it("kong.response.get_source() returns \"error\" if plugin runtime exception occurs, FTI-3200", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "runtime_exception"
          }
        })
        local body = assert.res_status(500, res)
        assert.same("body_filter", body)
        assert.equal("error", res.headers["X-Source"])
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
            hosts     = { "runs-init-worker.test" },
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
          }

          assert(helpers.start_kong {
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
            plugins = "short-circuit,init-worker-lua-error",
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
              ["Host"] = "runs-init-worker.test",
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

        it("protects against failed init_worker handler, FTI-2473", function()
          local logs = pl_file.read(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log)
          assert.matches([[worker initialization error: failed to execute the "init_worker" handler for plugin "init-worker-lua-error"]], logs, nil, true)
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
              hosts     = { "runs-init-worker.test" },
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
              }
            }))

            assert.res_status(201, res)

            local res, body
            helpers.wait_until(function()
              res = assert(proxy_client:get("/status/400", {
                headers = {
                  ["Host"] = "runs-init-worker.test",
                }
              }))

              return pcall(function()
                body = assert.res_status(200, res)
                assert.equal("true", res.headers["Kong-Init-Worker-Called"])
              end)
            end, 10)

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

  describe("Plugins triggering [#" .. strategy .. "] with TLS keepalive", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      -- Global configuration
      local service = bp.services:insert {
        name = "mock",
      }

      local route = bp.routes:insert {
        paths     = { "/route-1" },
        protocols = { "https" },
        service    = service,
      }

      bp.routes:insert {
        paths      = { "/route-2" },
        protocols  = { "https" },
        service    = service,
      }

      bp.plugins:insert {
        name    = "request-termination",
        route   = { id = route.id },
        config  = {
          status_code = 201,
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("certificate phase clears context, fix #7054", function()
      local proxy_client = helpers.proxy_ssl_client()

      local res = assert(proxy_client:get("/route-1/status/200"))
      assert.res_status(201, res)

      local res = assert(proxy_client:get("/route-2/status/200"))
      assert.res_status(200, res)
    end)
  end)
end
