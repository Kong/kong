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

      local route_grpc = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        service = assert(bp.services:insert {
          name = "grpc",
          url = "grpc://localhost:15002",
        }),
      })

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
          status_code = 418,
          message     = "I'm a teapot",
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

      bp.plugins:insert {
        name     = "correlation-id",
        route = { id = route_grpc.id },
        config   = {
          echo_downstream = true,
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

      it("increments the counter part #grpc", function()
        local ok, res = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-v"] = true,
          },
        }
        assert.truthy(ok)
        local id1  = string.match(res, "kong%-request%-id: (" .. UUID_COUNTER_PATTERN .. ")")
        assert.matches(UUID_COUNTER_PATTERN, id1)

        local ok, res = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-v"] = true,
          },
        }
        assert.truthy(ok)

        local id2  = string.match(res, "kong%-request%-id: (" .. UUID_COUNTER_PATTERN .. ")")
        assert.matches(UUID_COUNTER_PATTERN, id2)
        assert.not_equal(id1, id2)

        -- only one nginx worker in our test instance allows us
        -- to test this.
        local counter1 = string.match(id1, "#(%d)$")
        local counter2 = string.match(id2, "#(%d)$")
        assert(counter2 > counter1)
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

    it("does not preserve an already existing empty header", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"]            = "correlation2.com",
          ["Kong-Request-ID"] = ""
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local id   = json.headers["kong-request-id"]
      assert.not_equal("foobar", id)
    end)

    it("does not preserve an already existing header with space only", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"]            = "correlation2.com",
          ["Kong-Request-ID"] = " "
        }
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local id   = json.headers["kong-request-id"]
      assert.not_equal("foobar", id)
    end)

    it("executes with echo_downstream when access did not execute", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "correlation5.com",
        }
      })
      assert.response(res).has.status(418, res)
      local downstream_id = assert.response(res).has.header("kong-request-id")
      assert.matches(UUID_PATTERN, downstream_id)
    end)

    it("echoes incoming with echo_downstream when access did not execute", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          ["Host"] = "correlation5.com",
          ["kong-request-id"] = "my very personal id",
        }
      })
      assert.response(res).has.status(418, res)
      local downstream_id = assert.response(res).has.header("kong-request-id")
      assert.equals("my very personal id", downstream_id)
    end)
  end)
end
