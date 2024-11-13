local constants = require "kong.constants"
local helpers = require "spec.helpers"
local cjson = require "cjson"
local lower = string.lower
local split = require("kong.tools.string").split

local REMEMBER_ROLLING_TIMEOUT = 3600

for _, strategy in helpers.each_strategy() do
  describe("Plugin: Session (access) [#" .. strategy .. "]", function()
    local client, consumer, credential

    lazy_setup(function()
      local bp, db = helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "services",
        "consumers",
        "keyauth_credentials"
      }, { "ctx-checker" })

      local route1 = bp.routes:insert {
        paths    = {"/test1"},
        hosts = {"konghq.test"},
      }

      local route2 = bp.routes:insert {
        paths    = {"/test2"},
        hosts = {"konghq.test"},
      }

      local route3 = bp.routes:insert {
        paths    = {"/headers"},
        hosts = {"konghq.test"},
      }

      local route4 = bp.routes:insert {
        paths    = {"/headers"},
        hosts = {"mockbin.test"},
      }

      local route5 = bp.routes:insert {
        paths    = {"/test5"},
        hosts = {"httpbin.test"},
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
          cookie_same_site = "Lax",
          cookie_http_only = false,
          cookie_secure = false,
        }
      })

      assert(bp.plugins:insert {
        name = "session",
        route = {
          id = route3.id,
        },
      })

      assert(bp.plugins:insert {
        name = "session",
        route = {
          id = route4.id,
        },
      })

      bp.plugins:insert {
        name = "ctx-checker",
        route = { id = route4.id },
        config = {
          ctx_kind      = "ngx.ctx",
          ctx_set_field = "authenticated_groups",
          ctx_set_array = { "agents", "doubleagents" },
        }
      }

      assert(bp.plugins:insert {
        name = "session",
        route = {
          id = route5.id,
        },
        config = {
          remember_rolling_timeout = REMEMBER_ROLLING_TIMEOUT,
          remember = true,
        },
      })

      consumer = db.consumers:insert({username = "coop"})

      credential = bp.keyauth_credentials:insert {
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
        name = "key-auth",
        route = {
          id = route3.id,
        },
        config = {
          anonymous = anonymous.id
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = {
          id = route4.id,
        },
        config = {
          anonymous = anonymous.id
        }
      }

      bp.plugins:insert {
        name = "key-auth",
        route = {
          id = route5.id,
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

    describe("request", function()
      it("plugin attaches Set-Cookie and cookie response headers", function()
        client = helpers.proxy_ssl_client()
        local res = assert(client:send {
          method = "GET",
          path = "/test1/status/200",
          headers = {
            host = "konghq.test",
            apikey = "kong",
          },
        })
        assert.response(res).has.status(200)
        client:close()

        local cookie = assert.response(res).has.header("Set-Cookie")
        local cookie_name = split(cookie, "=")[1]
        assert.equal("session", cookie_name)

        -- e.g. ["Set-Cookie"] =
        --    "da_cookie=m1EL96jlDyQztslA4_6GI20eVuCmsfOtd6Y3lSo4BTY|15434724
        --    06|U5W4A6VXhvqvBSf4G_v0-Q|DFJMMSR1HbleOSko25kctHZ44oo; Path=/
        --    ; SameSite=Lax; Secure; HttpOnly"
        local cookie_parts = split(cookie, "; ")
        assert.equal("SameSite=Strict", cookie_parts[3])
        assert.equal("Secure", cookie_parts[4])
        assert.equal("HttpOnly", cookie_parts[5])
      end)

      it("cookie works as authentication after initial auth plugin", function()
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
        client:close()

        cookie = assert.response(res).has.header("Set-Cookie")
        assert.equal("da_cookie", split(cookie, "=")[1])

        local cookie_parts = split(cookie, "; ")
        assert.equal("SameSite=Lax", cookie_parts[3])
        assert.equal(nil, cookie_parts[4])
        assert.equal(nil, cookie_parts[5])

        -- use the cookie without the key to ensure cookie still lets them in
        request.headers.apikey = nil
        request.headers.cookie = cookie
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()
      end)

      it("plugin attaches Set-Cookie with max-age/expiry when cookie_persistent is true", function()
        client = helpers.proxy_ssl_client()
        local res = assert(client:send {
          method = "GET",
          path = "/test5/status/200",
          headers = {
            host = "httpbin.test",
            apikey = "kong",
          },
        })
        assert.response(res).has.status(200)
        client:close()

        local cookie = assert.response(res).has.header("Set-Cookie")
        local cookie_name = split(cookie[1], "=")[1]
        assert.equal("session", cookie_name)

        -- e.g. ["Set-Cookie"] =
        --    "session=m1EL96jlDyQztslA4_6GI20eVuCmsfOtd6Y3lSo4BTY|15434724
        --    06|U5W4A6VXhvqvBSf4G_v0-Q|DFJMMSR1HbleOSko25kctHZ44oo; Expires=Mon, 06 Jun 2022 08:30:27 GMT;
        --    Max-Age=3600; Path=/; SameSite=Lax; Secure; HttpOnly"
        local cookie_parts = split(cookie[2], "; ")
        print(cookie[2])
        assert.equal("Path=/", cookie_parts[2])
        assert.equal("SameSite=Strict", cookie_parts[3])
        assert.equal("Secure", cookie_parts[4])
        assert.equal("HttpOnly", cookie_parts[5])
        assert.truthy(string.match(cookie_parts[6], "^Expires=(.*)"))
        assert.equal("Max-Age=" .. REMEMBER_ROLLING_TIMEOUT, cookie_parts[7])
     end)

      it("consumer headers are set correctly on request", function()
        local res, cookie
        local request = {
          method = "GET",
          path = "/headers",
          headers = { host = "konghq.test", },
        }

        -- make a request with a valid key, grab the cookie for later
        request.headers.apikey = "kong"
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        cookie = assert.response(res).has.header("Set-Cookie")

        request.headers.apikey = nil
        request.headers.cookie = cookie

        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.equal(consumer.id, json.headers[lower(constants.HEADERS.CONSUMER_ID)])
        assert.equal(consumer.username, json.headers[lower(constants.HEADERS.CONSUMER_USERNAME)])
        if constants.HEADERS.CREDENTIAL_IDENTIFIER then
          assert.equal(credential.id, json.headers[lower(constants.HEADERS.CREDENTIAL_IDENTIFIER)])
        end
        assert.equal(nil, json.headers[lower(constants.HEADERS.ANONYMOUS)])
        assert.equal(nil, json.headers[lower(constants.HEADERS.CONSUMER_CUSTOM_ID)])
        assert.equal(nil, json.headers[lower(constants.HEADERS.AUTHENTICATED_GROUPS)])
      end)
    end)

    describe("authenticated_groups", function()
      it("groups are retrieved from session and headers are set", function()
        local res, cookie
        local request = {
          method = "GET",
          path = "/headers",
          headers = { host = "mockbin.test", },
        }

        -- make a request with a valid key, grab the cookie for later
        request.headers.apikey = "kong"
        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        cookie = assert.response(res).has.header("Set-Cookie")

        request.headers.apikey = nil
        request.headers.cookie = cookie

        client = helpers.proxy_ssl_client()
        res = assert(client:send(request))
        assert.response(res).has.status(200)
        client:close()

        local json = cjson.decode(assert.res_status(200, res))
        assert.equal('agents, doubleagents', json.headers[lower(constants.HEADERS.AUTHENTICATED_GROUPS)])
      end)
    end)
  end)
end
