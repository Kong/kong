local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"


function get_sid_from_cookie(cookie)
  local cookie_parts = utils.split(cookie, "; ")
  return utils.split(utils.split(cookie_parts[1], "|")[1], "=")[2]
end


for _, strategy in helpers.each_strategy({'postgres'}) do
  describe("Plugin: Session (kong storage adapter) [#" .. strategy .. "]", function()
    local client, bp, db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "sessions",
        "plugins",
        "routes",
        "services",
        "consumers",
        "keyauth_credentials",
      })

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
        route = {
          id = route1.id,
        },
        config = {
          storage = "kong",
          secret = "ultra top secret session",
        }
      })
      
      assert(bp.plugins:insert {
        name = "session",
        route = {
          id = route2.id,
        },
        config = {
          secret = "super secret session secret",
          storage = "kong",
          cookie_renew = 600,
          cookie_lifetime = 604,
        }
      })

      local consumer = bp.consumers:insert { username = "coop" }
      bp.keyauth_credentials:insert {
        key = "kong",
        consumer = {
          id = consumer.id
        },
      }

      local anonymous = bp.consumers:insert { username = "anon" }
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
      helpers.stop_kong(nil, true)
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
        
        ngx.sleep(2)

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie  
        res = assert(client:send(request))
        assert.response(res).has.status(200)

        -- one more time to ensure session was not destroyed or errored out
        res = assert(client:send(request))
        assert.response(res).has.status(200)

        -- make sure it's in the db
        local sid = get_sid_from_cookie(cookie)
        assert.equal(sid, db.sessions:select_by_session_id(sid).session_id)
      end)

      it("renews cookie", function()  
        local res, cookie
        local request = {
          method = "GET",
          path = "/test2/status/200",
          headers = { host = "httpbin.org", },
        }

        local function send_requests(request, number, step)
          local cookie = request.headers.cookie

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

        ngx.sleep(2)

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        
        -- renewal period, make sure requests still come through and
        -- if set-cookie header comes through, attach it to subsequent requests
        send_requests(request, 5, 0.5)
      end)

      it("destroys session on logout", function()  
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

        ngx.sleep(2)

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        res = assert(client:send(request))
        assert.response(res).has.status(200)

        -- session should be in the table initially
        local sid = get_sid_from_cookie(cookie)
        assert.equal(sid, db.sessions:select_by_session_id(sid).session_id)

        -- logout request
        res = assert(client:send({
          method = "DELETE",
          path = "/test2/status/200?session_logout=true",
          headers = {
            cookie = cookie,
            host = "httpbin.org",
          }
        }))

        assert.response(res).has.status(200)

        local found = db.sessions:select_by_session_id(sid)

        -- logged out, no sessions should be in the table
        assert.is_nil(found)
      end)
    end)
  end)
end
