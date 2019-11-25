local helpers = require "spec.helpers"
local cjson   = require "cjson"
local meta    = require "kong.meta"


local server_tokens = meta._SERVER_TOKENS


for _, strategy in helpers.each_strategy() do
  describe("Plugin: request-termination (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route1 = bp.routes:insert({
        hosts = { "api1.request-termination.com" },
      })

      local route2 = bp.routes:insert({
        hosts = { "api2.request-termination.com" },
      })

      local route3 = bp.routes:insert({
        hosts = { "api3.request-termination.com" },
      })

      local route4 = bp.routes:insert({
        hosts = { "api4.request-termination.com" },
      })

      local route5 = bp.routes:insert({
        hosts = { "api5.request-termination.com" },
      })

      local route6 = bp.routes:insert({
        hosts = { "api6.request-termination.com" },
      })

      local route7 = db.routes:insert({
        hosts = { "api7.request-termination.com" },
      })

      local route8 = bp.routes:insert({
        hosts = { "api8.request-termination.com" },
      })

      bp.plugins:insert {
        name   = "request-termination",
        route  = { id = route1.id },
        config = {},
      }

      bp.plugins:insert {
        name   = "request-termination",
        route  = { id = route2.id },
        config = {
          status_code = 404,
        },
      }

      bp.plugins:insert {
        name   = "request-termination",
        route  = { id = route3.id },
        config = {
          status_code = 406,
          message     = "Invalid",
        },
      }

      bp.plugins:insert {
        name   = "request-termination",
        route  = { id = route4.id },
        config = {
          body = "<html><body><h1>Service is down for maintenance</h1></body></html>",
        },
      }

      bp.plugins:insert {
        name   = "request-termination",
        route  = { id = route5.id },
        config = {
          status_code  = 451,
          content_type = "text/html",
          body         = "<html><body><h1>Service is down due to content infringement</h1></body></html>",
        },
      }

      bp.plugins:insert {
        name   = "request-termination",
        route  = { id = route6.id },
        config = {
          status_code = 503,
          body        = '{"code": 1, "message": "Service unavailable"}',
        },
      }

      bp.plugins:insert {
        name   = "request-termination",
        route  = { id = route7.id },
        config = {},
      }

      bp.plugins:insert {
        name   = "request-termination",
        route  = { id = route8.id },
        config = {
          status_code = 204
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if proxy_client and admin_client then
        proxy_client:close()
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    describe("status code and message", function()
      it("default status code and message", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "api1.request-termination.com"
          }
        })
        local body = assert.res_status(503, res)
        local json = cjson.decode(body)
        assert.same({ message = "Service unavailable" }, json)
      end)

      it("default status code and message with serviceless route", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "api7.request-termination.com"
          }
        })
        local body = assert.res_status(503, res)
        local json = cjson.decode(body)
        assert.same({ message = "Service unavailable" }, json)
      end)

      it("status code with default message", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "api2.request-termination.com"
          }
        })
        local body = assert.res_status(404, res)
        local json = cjson.decode(body)
        assert.same({ message = "Not found" }, json)
      end)

      it("status code with custom message", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "api3.request-termination.com"
          }
        })
        local body = assert.res_status(406, res)
        local json = cjson.decode(body)
        assert.same({ message = "Invalid" }, json)
      end)

      it("returns 204 without content length header", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/204",
          headers = {
            ["Host"] = "api8.request-termination.com"
          }
        })

        assert.res_status(204, res)
        assert.is_nil(res.headers["Content-Length"])
      end)

    end)

    describe("status code and body", function()
      it("default status code and body", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "api4.request-termination.com"
          }
        })
        local body = assert.res_status(503, res)
        assert.equal([[<html><body><h1>Service is down for maintenance</h1></body></html>]], body)
      end)

      it("status code with default message", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "api5.request-termination.com"
          }
        })
        local body = assert.res_status(451, res)
        assert.equal([[<html><body><h1>Service is down due to content infringement</h1></body></html>]], body)
      end)

      it("status code with custom message", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "api6.request-termination.com"
          }
        })
        local body = assert.res_status(503, res)
        local json = cjson.decode(body)
        assert.same({ code = 1, message = "Service unavailable" }, json)
      end)
    end)

    it("returns server tokens with Server header", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "api1.request-termination.com"
        }
      })

      assert.equal(server_tokens, res.headers["Server"])
    end)
  end)
end
