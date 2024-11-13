local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
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
      }, { "ctx-checker" })

      local route1 = bp.routes:insert {
        paths = {"/test1"},
        hosts = {"konghq.test"}
      }

      local route2 = bp.routes:insert {
        paths = {"/test2"},
        hosts = {"konghq.test"}
      }

      local route3 = bp.routes:insert {
        paths = {"/headers"},
        hosts = {"konghq.test"},
      }

      assert(bp.plugins:insert {
        name = "session",
        route = {
          id = route1.id,
        },
        config = {
          storage = "kong",
          secret = "ultra top secret session",
          response_headers = { "id", "timeout", "audience", "subject" }
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
          rolling_timeout = 4,
          response_headers = { "id", "timeout", "audience", "subject" }
        }
      })

      assert(bp.plugins:insert {
        name = "session",
        route = {
          id = route3.id,
        },
        config = {
          storage = "kong",
          secret = "ultra top secret session",
          response_headers = { "id", "timeout", "audience", "subject" }
        }
      })

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route3.id },
        config = {
          ctx_kind      = "ngx.ctx",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "beatles", "ramones" },
        }
      }

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
        name = "key-auth",
        route = {
          id = route3.id,
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
        plugins = "bundled, session, ctx-checker",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("kong adapter -", function()
      it("kong adapter stores consumer", function()
        local res, cookie
        local request = {
          method = "GET",
          path = "/test1/status/200",
          headers = { host = "konghq.test", },
        }

        -- make sure the anonymous consumer can't get in (request termination)
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(403)
        client:close()

        -- make a request with a valid key, grab the cookie for later
        request.headers.apikey = "kong"
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        cookie = assert.response(res).has.header("Set-Cookie")
        client:close()

        local sid = res.headers["Session-Id"]

        ngx.sleep(2)

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        -- one more time to ensure session was not destroyed or errored out
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        assert.equal(sid, db.sessions:select_by_session_id(sid).session_id)
      end)

      it("renews cookie", function()
        local res, cookie
        local request = {
          method = "GET",
          path = "/test2/status/200",
          headers = { host = "konghq.test", },
        }

        local function send_requests(request, number, step)
          local did_renew = false
          cookie = request.headers.cookie

          for _ = 1, number do
            request.headers.cookie = cookie
            client = helpers.proxy_ssl_client()
            res = assert(client:send(request))
            assert.response(res).has.status(200)
            did_renew = did_renew or res.headers['Set-Cookie'] ~= nil
            client:close()

            cookie = res.headers['Set-Cookie'] or cookie
            ngx.sleep(step)
          end

          return did_renew
        end

        -- make sure the anonymous consumer can't get in (request termination)
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(403)
        client:close()

        -- make a request with a valid key, grab the cookie for later
        request.headers.apikey = "kong"
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        cookie = assert.response(res).has.header("Set-Cookie")

        ngx.sleep(2)

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        -- renewal period, make sure requests still come through and
        -- if set-cookie header comes through, attach it to subsequent requests
        assert.is_true(send_requests(request, 7, 0.5))
      end)

      it("destroys session on logout", function()
        local res, cookie
        local request = {
          method = "GET",
          path = "/test2/status/200",
          headers = { host = "konghq.test", },
        }

        -- make sure the anonymous consumer can't get in (request termination)
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(403)
        client:close()

        -- make a request with a valid key, grab the cookie for later
        request.headers.apikey = "kong"
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        cookie = assert.response(res).has.header("Set-Cookie")
        client:close()

        local sid = res.headers["Session-Id"]

        ngx.sleep(2)

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        -- session should be in the table initially
        assert.equal(sid, db.sessions:select_by_session_id(sid).session_id)

        -- logout request
        client = helpers.proxy_ssl_client()
        res = assert(client:send({
          method = "DELETE",
          path = "/test2/status/200?session_logout=true",
          headers = {
            cookie = cookie,
            host = "konghq.test",
          }
        }))
        assert.response(res).has.status(200)
        client:close()

        local found, err = db.sessions:select_by_session_id(sid)

        -- logged out, no sessions should be in the table, without errors
        assert.is_nil(found)
        assert.is_nil(err)
      end)

      it("stores authenticated_groups", function()
        local res, cookie
        local request = {
          method = "GET",
          path = "/headers",
          headers = { host = "konghq.test", },
        }

        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(403)
        client:close()

        -- make a request with a valid key, grab the cookie for later
        request.headers.apikey = "kong"
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        cookie = assert.response(res).has.header("Set-Cookie")
        client:close()

        ngx.sleep(2)

        request.headers.apikey = nil
        request.headers.cookie = cookie
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        local json = cjson.decode(assert.res_status(200, res))
        assert.equal('beatles, ramones', json.headers['x-authenticated-groups'])
      end)
    end)
  end)
end
