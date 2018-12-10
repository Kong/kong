local helpers = require "spec.helpers"
local new_tab = require "table.new"

for _, strategy in helpers.each_strategy() do
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
          secret = "ultra top secret session",
        }
      })
      
      assert(bp.plugins:insert {
        name = "session",
        route_id = route2.id,
        config = {
          secret = "super secret session secret",
          storage = "kong",
          cookie_renew = 600,
          cookie_lifetime = 601,
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
        route_id = route1.id,
        config = {
          anonymous = anonymous.id
        }
      }

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
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_ssl_client()
    end)

    after_each(function()
      if client then client:close() end
    end)      

    describe("kong adapter - ", function()
      it("kong adapter stores consumer", function()  
        local res, cookie
        local request = {
          method = "GET",
          path = "/test1/status/200",
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

        ngx.sleep(0.1)

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        res = assert(client:send(request))
        assert.response(res).has.status(200)

        -- one more time to ensure session was not destroyed or errored out
        res = assert(client:send(request))
        assert.response(res).has.status(200)
      end)

      it("renews cookie", function()  
        local res, cookie
        local request = {
          method = "GET",
          path = "/test2/status/200",
          headers = { host = "httpbin.org", },
        }

        function send_requests(request, number, step)
          local cookie = request.headers.cookie

          local t = new_tab(number, 0)
          for i = 1, number do
            request.headers.cookie = cookie
            res = assert(client:send(request))
            assert.response(res).has.status(200)
            cookie = res.headers['Set-Cookie'] or cookie
            ngx.sleep(step)
          end
        end

        -- make sure the anonymous consumer can't get in (request termination)
        res = assert(client:send(request))
          assert.response(res).has.status(403)
  
        -- make a request with a valid key, grab the cookie for later
        request.headers.apikey = "kong"
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        cookie = assert.response(res).has.header("Set-Cookie")

        ngx.sleep(0.1)

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        
        -- renewal period, make sure requests still come through and
        -- if set-cookie header comes through, attach it to subsequent requests
        send_requests(request, 5, 0.5)
      end)
    end)
  end)
end
