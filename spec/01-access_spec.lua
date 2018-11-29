local utils = require "kong.tools.utils"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: Session (access) [#" .. strategy .. "]", function()
    local client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local service = assert(bp.services:insert {
        path = "/",
        protocol = "http",
        host = "httpbin.org",
      })

      local route1 = bp.routes:insert {
        paths    = {"/test1"},
        service = service1,
      }

      local route2 = bp.routes:insert {
        paths    = {"/test2"},
        service = service1,
      }

      assert(bp.plugins:insert {
        name = "session",
        route_id = route1.id,
      })

      assert(bp.plugins:insert {
        name = "session",
        route_id = route2.id,
        config = {
          cookie_name = "da_cookie",
          cookie_samesite = "Lax",
          cookie_httponly = false,
          cookie_secure = false,
        }
      })

      assert(helpers.start_kong {
        custom_plugins = "session",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",        
      })
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_ssl_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("request", function()
      it("plugin attaches Set-Cookie and cookie response headers", function()
        local res = assert(client:send {
          method = "GET",
          path = "/test1/status/200",
          headers = {
            host = "httpbin.org"
          }
        })

        assert.response(res).has.status(200)

        local cookie = assert.response(res).has.header("Set-Cookie")
        local cookie_name = utils.split(cookie, "=")[1]
        assert.equal("session", cookie_name)
        
        local cookie_parts = utils.split(cookie, "; ")
        assert.equal("SameSite=Strict", cookie_parts[3])
        assert.equal("Secure", cookie_parts[4])
        assert.equal("HttpOnly", cookie_parts[5])
      end)

      it("plugin attaches cookie from configs", function()
        local res = assert(client:send {
          method = "GET",
          path = "/test2/status/200",
          headers = {
            host = "httpbin.org"
          }
        })

        assert.response(res).has.status(200)
        
        local cookie = assert.response(res).has.header("Set-Cookie")
        local cookie_name = utils.split(cookie, "=")[1]
        assert.equal("da_cookie", cookie_name)
        
        local cookie_parts = utils.split(cookie, "; ")
        assert.equal("SameSite=Lax", cookie_parts[3])
        assert.equal(nil, cookie_parts[4])
        assert.equal(nil, cookie_parts[5])
      end)
    end)
  end)
end
