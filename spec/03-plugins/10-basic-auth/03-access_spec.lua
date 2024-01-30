local helpers = require "spec.helpers"
local cjson   = require "cjson"
local meta    = require "kong.meta"
local utils   = require "kong.tools.utils"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: basic-auth (access) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "basicauth_credentials",
      })

      local consumer = bp.consumers:insert {
        username = "bob",
      }

      local anonymous_user = bp.consumers:insert {
        username = "no-body",
      }

      local route1 = bp.routes:insert {
        hosts = { "basic-auth1.test" },
      }

      local route2 = bp.routes:insert {
        hosts = { "basic-auth2.test" },
      }

      local route3 = bp.routes:insert {
        hosts = { "basic-auth3.test" },
      }

      local route4 = bp.routes:insert {
        hosts = { "basic-auth4.test" },
      }

      local route5 = bp.routes:insert {
        hosts = { "basic-auth5.test" },
      }

      local route_grpc = assert(bp.routes:insert {
        protocols = { "grpc" },
        paths = { "/hello.HelloService/" },
        service = assert(bp.services:insert {
          name = "grpc",
          url = helpers.grpcbin_url,
        }),
      })

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route1.id },
        config = {
          realm = "test-realm",
        }
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route_grpc.id },
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route2.id },
        config   = {
          hide_credentials = true,
        },
      }

      bp.basicauth_credentials:insert {
        username = "bob",
        password = "kong",
        consumer = { id = consumer.id },
      }

      bp.basicauth_credentials:insert {
        username = "user123",
        password = "password123",
        consumer = { id = consumer.id },
      }

      bp.basicauth_credentials:insert {
        username = "user321",
        password = "password:123",
        consumer = { id = consumer.id },
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route3.id },
        config   = {
          anonymous = anonymous_user.id,
        },
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route4.id },
        config   = {
          anonymous = utils.uuid(), -- a non-existing consumer id
        },
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route5.id },
        config   = {
          anonymous = anonymous_user.username,
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

    describe("Unauthorized", function()
      describe("when realm is configured", function()
        it("returns Unauthorized on missing credentials", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["Host"] = "basic-auth1.test"
            }
          })
          local body = assert.res_status(401, res)
          local json = cjson.decode(body)
          assert.not_nil(json)
          assert.matches("Unauthorized", json.message)
          assert.equal('Basic realm="test-realm"', res.headers["WWW-Authenticate"])
        end)
      end)

      describe("when realm is default", function()
        it("returns Unauthorized on missing credentials", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              ["Host"] = "basic-auth2.test"
            }
          })
          local body = assert.res_status(401, res)
          local json = cjson.decode(body)
          assert.not_nil(json)
          assert.matches("Unauthorized", json.message)
          assert.equal('Basic realm="service"', res.headers["WWW-Authenticate"])
        end)
      end)
    end)

    describe("Unauthorized", function()

      it("returns 401 Unauthorized on invalid credentials in Authorization", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Authorization"] = "foobar",
            ["Host"]          = "basic-auth1.test"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("Unauthorized", json.message)
        assert.equal('Basic realm="test-realm"', res.headers["WWW-Authenticate"])
      end)

      it("returns 401 Unauthorized on invalid credentials in Proxy-Authorization", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Proxy-Authorization"] = "foobar",
            ["Host"]                = "basic-auth1.test"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("Unauthorized", json.message)
        assert.equal('Basic realm="test-realm"', res.headers["WWW-Authenticate"])
      end)

      it("returns 401 Unauthorized on password only", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Authorization"] = "Basic a29uZw==",
            ["Host"]          = "basic-auth1.test"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("Unauthorized", json.message)
        assert.equal('Basic realm="test-realm"', res.headers["WWW-Authenticate"])
      end)

      it("returns 401 Unauthorized on username only", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Authorization"] = "Basic Ym9i",
            ["Host"]          = "basic-auth1.test"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("Unauthorized", json.message)
        assert.equal('Basic realm="test-realm"', res.headers["WWW-Authenticate"])
      end)

      it("rejects gRPC call without credentials", function()
        local ok, err = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {},
        }
        assert.falsy(ok)
        assert.matches("Code: Unauthenticated", err)
      end)

      it("accepts authorized gRPC calls", function()
        local ok, res = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-H"] = "'Authorization: Basic Ym9iOmtvbmc='",
          },
        }
        assert.truthy(ok)
        assert.same({ reply = "hello noname" }, cjson.decode(res))
      end)

      it("authenticates valid credentials in Authorization", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Authorization"] = "Basic Ym9iOmtvbmc=",
            ["Host"]          = "basic-auth1.test"
          }
        })
        assert.res_status(200, res)
      end)

      it("authenticates valid credentials in Authorization", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzd29yZDEyMw==",
            ["Host"]          = "basic-auth1.test"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal('bob', body.headers["x-consumer-username"])
        assert.equal('user123', body.headers["x-credential-identifier"])
      end)

      it("authenticates with a password containing ':'", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/request",
          headers = {
            ["Authorization"] = "Basic dXNlcjMyMTpwYXNzd29yZDoxMjM=",
            ["Host"] = "basic-auth1.test"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal("bob", body.headers["x-consumer-username"])
        assert.equal("user321", body.headers["x-credential-identifier"])
      end)

      it("returns 401 for valid Base64 encoding", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Authorization"] = "Basic adXNlcjEyMzpwYXNzd29yZDEyMw==",
            ["Host"]          = "basic-auth1.test"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.not_nil(json)
        assert.matches("Unauthorized", json.message)
        assert.equal('Basic realm="test-realm"', res.headers["WWW-Authenticate"])
      end)

      it("authenticates valid credentials in Proxy-Authorization", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Proxy-Authorization"] = "Basic Ym9iOmtvbmc=",
            ["Host"]                = "basic-auth1.test"
          }
        })
        assert.res_status(200, res)
      end)

    end)

    describe("Consumer headers", function()

      it("sends Consumer headers to upstream", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic Ym9iOmtvbmc=",
            ["Host"]          = "basic-auth1.test"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_string(json.headers["x-consumer-id"])
        assert.equal("bob", json.headers["x-consumer-username"])
        assert.equal("bob", json.headers["x-credential-identifier"])
      end)

    end)

    describe("config.hide_credentials", function()

      it("false sends key to upstream", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic Ym9iOmtvbmc=",
            ["Host"]          = "basic-auth1.test"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("Basic Ym9iOmtvbmc=", json.headers.authorization)
      end)

      it("true doesn't send key to upstream", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic Ym9iOmtvbmc=",
            ["Host"]          = "basic-auth2.test"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_nil(json.headers.authorization)
      end)

    end)


    describe("config.anonymous", function()

      it("works with right credentials and anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzd29yZDEyMw==",
            ["Host"]          = "basic-auth3.test"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal('bob', body.headers["x-consumer-username"])
        assert.equal('user123', body.headers["x-credential-identifier"])
        assert.is_nil(body.headers["x-anonymous-consumer"])
      end)

      it("works with wrong credentials and anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "basic-auth3.test"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal('true', body.headers["x-anonymous-consumer"])
        assert.equal('no-body', body.headers["x-consumer-username"])
        assert.equal(nil, body.headers["x-credential-identifier"])
      end)

      it("works with wrong credentials and username in anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "basic-auth5.test"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal('true', body.headers["x-anonymous-consumer"])
        assert.equal('no-body', body.headers["x-consumer-username"])
      end)

      it("errors when anonymous user doesn't exist", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "basic-auth4.test"
          }
        })
        assert.response(res).has.status(500)
      end)

    end)

  end)

  describe("Plugin: basic-auth (access) [#" .. strategy .. "]", function()
    local proxy_client
    local user1
    local user2
    local anonymous

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "basicauth_credentials",
        "keyauth_credentials",
      })

      anonymous = bp.consumers:insert {
        username = "Anonymous",
      }

      user1 = bp.consumers:insert {
        username = "Mickey",
      }

      user2 = bp.consumers:insert {
        username = "Aladdin",
      }

      local service1 = bp.services:insert {
        path = "/request",
      }

      local service2 = bp.services:insert {
        path = "/request",
      }

      local route1 = bp.routes:insert {
        hosts   = { "logical-and.test" },
        service = service1,
      }

      local route2 = bp.routes:insert {
        hosts   = { "logical-or.test" },
        service = service2,
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route1.id },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route1.id },
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route2.id },
        config   = {
          anonymous = anonymous.id,
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route2.id },
        config   = {
          anonymous = anonymous.id,
        },
      }

      bp.keyauth_credentials:insert({
        key      = "Mouse",
        consumer = { id = user1.id },
      })

      bp.basicauth_credentials:insert {
        username = "Aladdin",
        password = "OpenSesame",
        consumer = { id = user2.id },
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

    describe("multiple auth without anonymous, logical AND", function()

      it("passes with all credentials provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-and.test",
            ["apikey"]        = "Mouse",
            ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert(id == user1.id or id == user2.id)
      end)

      it("fails 401, with only the first credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "logical-and.test",
            ["apikey"] = "Mouse",
          }
        })
        assert.response(res).has.status(401)
      end)

      it("fails 401, with only the second credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-and.test",
            ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
          }
        })
        assert.response(res).has.status(401)
        assert.equal('Key realm="' .. meta._NAME .. '"', res.headers["WWW-Authenticate"])
      end)

      it("fails 401, with no credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "logical-and.test",
          }
        })
        assert.response(res).has.status(401)
        assert.equal('Key realm="' .. meta._NAME .. '"', res.headers["WWW-Authenticate"])
      end)

    end)

    describe("multiple auth with anonymous, logical OR", function()

      it("passes with all credentials provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-or.test",
            ["apikey"]        = "Mouse",
            ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert(id == user1.id or id == user2.id)
      end)

      it("passes with only the first credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "logical-or.test",
            ["apikey"] = "Mouse",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert.equal(user1.id, id)
      end)

      it("passes with only the second credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-or.test",
            ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.no.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.not_equal(id, anonymous.id)
        assert.equal(user2.id, id)
      end)

      it("passes with no credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "logical-or.test",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.equal(id, anonymous.id)
      end)

    end)
  end)

  describe("Plugin: basic-auth (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local anonymous

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "basicauth_credentials",
        "keyauth_credentials",
      })

      anonymous = bp.consumers:insert {
        username = "Anonymous",
      }

      local service = bp.services:insert {
        path = "/request",
      }

      local route = bp.routes:insert {
        hosts   = { "anonymous-with-username.test" },
        service = service,
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route.id },
        config = {
          anonymous = anonymous.username,
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
      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    it("consumer cache consistency", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "anonymous-with-username.test",
        },
      })
      assert.response(res).has.status(200)
      local body = assert.response(res).has.jsonbody()
      assert.are.equal("true", body.headers["x-anonymous-consumer"])
      assert.are.equal(anonymous.id, body.headers["x-consumer-id"])
      assert.are.equal(anonymous.username, body.headers["x-consumer-username"])

      local res = assert(admin_client:send {
        method = "DELETE",
        path = "/consumers/" .. anonymous.username,
      })
      assert.res_status(204, res)

      ngx.sleep(1) -- wait for cache invalidation

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["Host"] = "anonymous-with-username.test",
        }
      })
      assert.res_status(500, res)
    end)

  end)
end
