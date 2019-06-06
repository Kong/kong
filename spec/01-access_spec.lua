local utils = require "kong.tools.utils"
local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: Session (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "services",
        "consumers",
        "keyauth_credentials"
      })

      local route1 = bp.routes:insert {
        paths    = {"/test1"},
        hosts = {"httpbin.org"},
      }

      local route2 = bp.routes:insert {
        paths    = {"/test2"},
        hosts = {"httpbin.org"},
      }

      assert(bp.plugins:insert {
        name = "session",
        route = {
          id = route1.id,
        },
      })

      assert(bp.plugins:insert {
        name = "session",
        route = {
          id = route2.id,
        },
        config = {
          cookie_name = "da_cookie",
          cookie_samesite = "Lax",
          cookie_httponly = false,
          cookie_secure = false,
        }
      })

      local consumer = bp.consumers:insert { username = "coop", }
      bp.keyauth_credentials:insert {
        key = "kong",
        consumer = {
          id = consumer.id,
        },
      }

      local anonymous = bp.consumers:insert { username = "anon", }
      bp.plugins:insert {
        name = "key-auth",
        route = {
          id = route1.id,
        },
        config = {
          anonymous = anonymous.id
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = {
          id = route2.id,
        },
        config = {
          anonymous = anonymous.id
        }
      }

      bp.plugins:insert {
        name = "request-termination",
        consumer = {
          id = anonymous.id,
        },
        config = {
          status_code = 403,
          message = "So it goes.",
        }
      }

      assert(helpers.start_kong {
        plugins = "bundled, session",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
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
            host = "httpbin.org",
            apikey = "kong",
          },
        })

        assert.response(res).has.status(200)

        local cookie = assert.response(res).has.header("Set-Cookie")
        local cookie_name = utils.split(cookie, "=")[1]
        assert.equal("session", cookie_name)

        -- e.g. ["Set-Cookie"] = 
        --    "da_cookie=m1EL96jlDyQztslA4_6GI20eVuCmsfOtd6Y3lSo4BTY.|15434724
        --    06|U5W4A6VXhvqvBSf4G_v0-Q..|DFJMMSR1HbleOSko25kctHZ44oo.; Path=/
        --    ; SameSite=Lax; Secure; HttpOnly"
        local cookie_parts = utils.split(cookie, "; ")
        assert.equal("SameSite=Strict", cookie_parts[3])
        assert.equal("Secure", cookie_parts[4])
        assert.equal("HttpOnly", cookie_parts[5])
      end)

      it("cookie works as authentication after initial auth plugin", function()
        local res, cookie
        local request = {
          method = "GET",
          path = "/test2/status/200",
          headers = { host = "httpbin.org", },
        }

        -- make sure the anonymous consumer can't get in (request termination)
        res = assert(client:send(request))
        assert.response(res).has.status(403)

        -- make a request with a valid key, grab the cookie for later
        request.headers.apikey = "kong"
        res = assert(client:send(request))
        assert.response(res).has.status(200)

        cookie = assert.response(res).has.header("Set-Cookie")
        assert.equal("da_cookie", utils.split(cookie, "=")[1])

        local cookie_parts = utils.split(cookie, "; ")
        assert.equal("SameSite=Lax", cookie_parts[3])
        assert.equal(nil, cookie_parts[4])
        assert.equal(nil, cookie_parts[5])

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        res = assert(client:send(request))
        assert.response(res).has.status(200)
      end)
    end)
  end)
end
