local utils = require "kong.tools.utils"
local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy('postgres') do
  describe("Plugin: Session (kong storage adapter) [#" .. strategy .. "]", function()
    local client, bp

    setup(function()
      bp = helpers.get_db_utils(strategy)

      local route1 = bp.routes:insert {
        paths    = {"/test1"},
        hosts = {"httpbin.org"}
      }

      local route2 = bp.routes:insert {
        paths    = {"/test2"},
        hosts = {"httpbin.org"}
      }

      assert(bp.plugins:insert {
        name = "session",
        route_id = route1.id,
        config = {
          storage = "kong",
        }
      })

      assert(bp.plugins:insert {
        name = "session",
        route_id = route2.id,
        config = {
          cookie_name = "da_cookie",
          storage = "kong"
        }
      })

      local consumer = bp.consumers:insert { username = "coop" }
      bp.keyauth_credentials:insert {
        key = "kong",
        consumer_id = consumer.id,
      }

      local anonymous = bp.consumers:insert { username = "anon" }
      bp.plugins:insert {
        name = "key-auth",
        route_id = route2.id,
        config = {
          anonymous = anonymous.id
        }
      }

      bp.plugins:insert {
        name = "request-termination",
        consumer_id = anonymous.id,
        config = {
          status_code = 403,
          message = "So it goes.",
        }
      }

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

    describe("kong adapter - ", function()
      it("uses kong adapter successfully", function()
        local res = assert(client:send {
          method = "GET",
          path = "/test1/status/200",
          headers = {
            host = "httpbin.org",
          },
        })
  
        assert.response(res).has.status(200)
  
        local cookie = assert.response(res).has.header("Set-Cookie")
        local cookie_name = utils.split(cookie, "=")[1]
        local cookie_val = utils.split(utils.split(cookie, "=")[2], ";")[1]
        assert.equal("session", cookie_name)
  
        res = assert(client:send {
          method = "GET",
          path = "/test1/status/200",
          headers = {
            host = "httpbin.org",
            cookie = cookie,
          },
        })
  
        assert.response(res).has.status(200)
        local cookie2 = assert.response(res).has.header("Set-Cookie")
        local cookie_val2 = utils.split(utils.split(cookie2, "=")[2], ";")[1]
        assert.equal(cookie_val, cookie_val2)
      end)

      it("kong adapter stores consumer", function()  
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
  
        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        res = assert(client:send(request))
        assert.response(res).has.status(200)
      end)
    end)  
  end)
end
