local helpers = require "spec.helpers"
local cjson   = require "cjson"


local UUID_PATTERN         = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
local UUID_COUNTER_PATTERN = UUID_PATTERN .. "#%d"
local TRACKER_PATTERN      = "%d+%.%d+%.%d+%.%d+%-%d+%-%d+%-%d+%-%d+%-%d%d%d%d%d%d%d%d%d%d%.%d%d%d"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: correlation-id (access) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, nil, { "error-generator-last" })

      local route1 = bp.routes:insert {
        hosts = { "correlation1.com" },
      }

      local route2 = bp.routes:insert {
        hosts = { "correlation2.com" },
      }

      local route3 = bp.routes:insert {
        hosts = { "correlation3.com" },
      }

      local route4 = bp.routes:insert {
        hosts = { "correlation-tracker.com" },
      }

      local route5 = bp.routes:insert {
        hosts = { "correlation5.com" },
      }

      local mock_service = bp.services:insert {
        host = "127.0.0.2",
        port = 26865,
      }

      local route6 = bp.routes:insert {
        hosts     = { "correlation-timeout.com" },
        service   = mock_service,
      }

      local route7 = bp.routes:insert {
        hosts     = { "correlation-error.com" },
      }

      bp.plugins:insert {
        name     = "correlation-id",
        route = { id = route1.id },
      }

      bp.plugins:insert {
        name     = "correlation-id",
        route = { id = route2.id },
        config   = {
          header_name = "Foo-Bar-Id",
        },
      }

      bp.plugins:insert {
        name     = "correlation-id",
        route = { id = route3.id },
        config   = {
          generator       = "uuid",
          echo_downstream = true,
        },
      }

      bp.plugins:insert {
        name     = "correlation-id",
        route = { id = route4.id },
        config   = {
          generator = "tracker",
        },
      }

      bp.plugins:insert {
        name     = "correlation-id",
        route = { id = route5.id },
        config   = {
          generator       = "uuid",
          echo_downstream = true,
        },
      }

      bp.plugins:insert {
        name     = "request-termination",
        route = { id = route5.id },
        config   = {
          status_code = 200,
          message     = "Success",
        },
      }

      bp.plugins:insert {
        name     = "correlation-id",
        route = { id = route6.id },
        config   = {
          generator       = "uuid",
          echo_downstream = true,
        },
      }

      bp.plugins:insert {
        name     = "correlation-id",
        route = { id = route7.id },
        config   = {
          generator       = "uuid",
          echo_downstream = true,
        },
      }

      bp.plugins:insert {
        name     = "error-generator-last",
        route = { id = route7.id },
        config   = {
          access = true,
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("uuid-worker generator", function()
      it("increments the counter part", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation1.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local id1  = json.headers["kong-request-id"] -- header received by upstream (mock_upstream)
        assert.matches(UUID_COUNTER_PATTERN, id1)

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation1.com"
          }
        })

        body = assert.res_status(200, res)
        json = cjson.decode(body)

        local id2 = json.headers["kong-request-id"] -- header received by upstream (mock_upstream)
        assert.matches(UUID_COUNTER_PATTERN, id2)
        assert.not_equal(id1, id2)

        -- only one nginx worker in our test instance allows us
        -- to test this.
        local counter1 = string.match(id1, "#(%d)$")
        local counter2 = string.match(id2, "#(%d)$")
        assert.equal("1", counter1)
        assert.equal("2", counter2)
      end)
    end)

    describe("uuid generator", function()
      it("generates a unique UUID for every request", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation3.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local id1  = json.headers["kong-request-id"] -- header received by upstream (mock_upstream)
        assert.matches(UUID_PATTERN, id1)

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation3.com"
          }
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        local id2 = json.headers["kong-request-id"] -- header received by upstream (mock_upstream)
        assert.matches(UUID_PATTERN, id2)
        assert.not_equal(id1, id2)
      end)
    end)

    describe("tracker generator", function()
      it("generates a unique tracker id for every request", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation-tracker.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local id1  = json.headers["kong-request-id"]
        assert.matches(TRACKER_PATTERN, id1)

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation-tracker.com"
          }
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        local id2 = json.headers["kong-request-id"]
        assert.matches(TRACKER_PATTERN, id2)
        assert.not_equal(id1, id2)
      end)
    end)

    describe("config options", function()
      it("echo_downstream sends uuid back to client", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation3.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local upstream_id   = json.headers["kong-request-id"] -- header received by upstream (mock_upstream)
        local downstream_id =  res.headers["kong-request-id"] -- header received by downstream (client)
        assert.matches(UUID_PATTERN, upstream_id)
        assert.equal(upstream_id, downstream_id)
      end)
      it("echo_downstream sends uuid back to client even when upstream timeouts", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation-timeout.com"
          }
        })
        assert.res_status(502, res)
        assert.matches(UUID_PATTERN, res.headers["kong-request-id"])
      end)
      it("echo_downstream sends uuid back to client even there is a runtime error", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation-error.com"
          }
        })
        assert.res_status(500, res)
        assert.matches(UUID_PATTERN, res.headers["kong-request-id"])
      end)
      it("echo_downstream does not send uuid back to client if not asked", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation2.com"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["kong-request-id"]) -- header received by downstream (client)
      end)
      it("uses a custom header name", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "correlation2.com"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local id   = json.headers["foo-bar-id"] -- header received by upstream (mock_upstream)
        assert.matches(UUID_PATTERN, id)
      end)
    end)

    it("preserves an already existing header", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"]            = "correlation2.com",
          ["Kong-Request-ID"] = "foobar"
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local id   = json.headers["kong-request-id"]
      assert.equal("foobar", id)
    end)

    it("executes with echo_downstream when access did not execute", function()
      -- Regression test for GH issue #3924
      -- https://github.com/Kong/kong/issues/3924
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "correlation5.com",
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same({ message = "Success" }, json)
    end)
  end)
end
