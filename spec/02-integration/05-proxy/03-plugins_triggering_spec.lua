local helpers = require "spec.helpers"


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
        local utils = require "kong.tools.utils"
        local cjson = require "cjson"
        local pl_path = require "pl.path"
        local pl_file = require "pl.file"
        local pl_stringx = require "pl.stringx"

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
        local utils = require "kong.tools.utils"
        local cjson = require "cjson"
        local pl_path = require "pl.path"
        local pl_file = require "pl.file"
        local pl_stringx = require "pl.stringx"
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
  end)
end
