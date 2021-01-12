local helpers = require "spec.helpers"
local cjson   = require "cjson"
local meta    = require "kong.meta"
local utils   = require "kong.tools.utils"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: key-auth (access) [#" .. strategy .. "]", function()
    local proxy_client
    local kong_cred

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local anonymous_user = bp.consumers:insert {
        username = "no-body",
      }

      local consumer = bp.consumers:insert {
        username = "bob"
      }

      local route1 = bp.routes:insert {
        hosts = { "key-auth1.com" },
      }

      local route2 = bp.routes:insert {
        hosts = { "key-auth2.com" },
      }

      local route3 = bp.routes:insert {
        hosts = { "key-auth3.com" },
      }

      local route4 = bp.routes:insert {
        hosts = { "key-auth4.com" },
      }

      local route5 = bp.routes:insert {
        hosts = { "key-auth5.com" },
      }

      local route6 = bp.routes:insert {
        hosts = { "key-auth6.com" },
      }

      local service7 = bp.services:insert{
        protocol = "http",
        port     = 80,
        host     = "mockbin.com",
      }

      local route7 = bp.routes:insert {
        hosts      = { "key-auth7.com" },
        service    = service7,
        strip_path = true,
      }

      local route8 = bp.routes:insert {
        hosts = { "key-auth8.com" },
      }

      local route9 = bp.routes:insert {
        hosts = { "key-auth9.com" },
      }

      local route10 = bp.routes:insert {
        hosts = { "key-auth10.com" },
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
        name     = "key-auth",
        route = { id = route1.id },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route2.id },
        config   = {
          hide_credentials = true,
        },
      }

      kong_cred = bp.keyauth_credentials:insert {
        key      = "kong",
        consumer = { id = consumer.id },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route3.id },
        config   = {
          anonymous = anonymous_user.id,
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route4.id },
        config   = {
          anonymous = utils.uuid(),  -- unknown consumer
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route5.id },
        config   = {
          key_in_body = true,
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route6.id },
        config   = {
          key_in_body      = true,
          hide_credentials = true,
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route7.id },
        config   = {
          run_on_preflight = false,
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route8.id },
        config = {
          key_names = { "api_key", },
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route9.id },
        config = {
          key_names = { "api-key", },
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route10.id },
        config = {
          anonymous = anonymous_user.username,
        },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route_grpc.id },
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
      it("returns 200 on OPTIONS requests if run_on_preflight is false", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          path    = "/status/200",
          headers = {
            ["Host"] = "key-auth7.com"
          }
        })
        assert.res_status(200, res)
      end)
      it("returns Unauthorized on OPTIONS requests if run_on_preflight is true", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          path    = "/status/200",
          headers = {
            ["Host"] = "key-auth1.com"
          }
        })
        assert.res_status(401, res)
        local body = assert.res_status(401, res)
        assert.same({message = "No API key found in request"}, cjson.decode(body))
      end)
      it("returns Unauthorized on missing credentials", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "key-auth1.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No API key found in request" }, json)
      end)
      it("returns Unauthorized on empty key header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "key-auth1.com",
            ["apikey"] = "",
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No API key found in request" }, json)
      end)
      it("returns Unauthorized on empty key querystring", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey",
          headers = {
            ["Host"] = "key-auth1.com",
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No API key found in request" }, json)
      end)
      it("returns WWW-Authenticate header on missing credentials", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "key-auth1.com"
          }
        })
        res:read_body()
        assert.equal('Key realm="' .. meta._NAME .. '"', res.headers["WWW-Authenticate"])
      end)
    end)

    describe("key in querystring", function()
      it("authenticates valid credentials", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            ["Host"] = "key-auth1.com",
          }
        })
        assert.res_status(200, res)
      end)
      it("returns 401 Unauthorized on invalid key", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=123",
          headers = {
            ["Host"] = "key-auth1.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "Invalid authentication credentials" }, json)
      end)
      it("handles duplicated key in querystring", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200?apikey=kong&apikey=kong",
          headers = {
            ["Host"] = "key-auth1.com"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "Duplicate API key found" }, json)
      end)
    end)

    describe("key in request body", function()
      for _, type in pairs({ "application/x-www-form-urlencoded", "application/json", "multipart/form-data" }) do
        describe(type, function()
          it("authenticates valid credentials", function()
            local res = assert(proxy_client:send {
              path    = "/request",
              headers = {
                ["Host"]         = "key-auth5.com",
                ["Content-Type"] = type,
              },
              body    = {
                apikey = "kong",
              }
            })
            assert.res_status(200, res)
          end)
          it("authenticates valid credentials in query", function()
            local res = assert(proxy_client:send {
              path    = "/request?apikey=kong",
              headers = {
                ["Host"]         = "key-auth5.com",
                ["Content-Type"] = type,
              },
              body    = {
                non_apikey = "kong",
              }
            })
            assert.res_status(200, res)
          end)
          it("authenticates valid credentials in header", function()
            local res = assert(proxy_client:send {
              path    = "/request?apikey=kong",
              headers = {
                ["Host"]         = "key-auth5.com",
                ["Content-Type"] = type,
                ["apikey"]       = "kong",
              },
              body    = {
                non_apikey = "kong",
              }
            })
            assert.res_status(200, res)
          end)
          it("returns 401 Unauthorized on invalid key", function()
            local res = assert(proxy_client:send {
              path    = "/status/200",
              headers = {
                ["Host"]         = "key-auth5.com",
                ["Content-Type"] = type,
              },
              body    = {
                apikey = "123",
              }
            })
            local body = assert.res_status(401, res)
            local json = cjson.decode(body)
            assert.same({ message = "Invalid authentication credentials" }, json)
          end)

          -- lua-multipart doesn't currently handle duplicates at all.
          -- form-url encoded client will encode duplicated keys as apikey[1]=kong&apikey[2]=kong
          if type == "application/json" then
            it("handles duplicated key", function()
              local res = assert(proxy_client:send {
                method  = "POST",
                path    = "/status/200",
                headers = {
                  ["Host"]         = "key-auth5.com",
                  ["Content-Type"] = type,
                },
                body = {
                  apikey = { "kong", "kong" },
                },
              })
              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.same({ message = "Duplicate API key found" }, json)
            end)
          end

          if type == "application/x-www-form-urlencoded" then
            it("handles duplicated key", function()
              local res = proxy_client:post("/status/200", {
                body = "apikey=kong&apikey=kong",
                headers = {
                  ["Host"]         = "key-auth5.com",
                  ["Content-Type"] = type,
                },
              })
              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.same({ message = "Duplicate API key found" }, json)
            end)

            it("does not identify apikey[] as api keys", function()
              local res = proxy_client:post("/status/200", {
                body = "apikey[]=kong&apikey[]=kong",
                headers = {
                  ["Host"]         = "key-auth5.com",
                  ["Content-Type"] = type,
                },
              })
              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.same({ message = "No API key found in request" }, json)
            end)

            it("does not identify apikey[1] as api keys", function()
              local res = proxy_client:post("/status/200", {
                body = "apikey[1]=kong&apikey[1]=kong",
                headers = {
                  ["Host"]         = "key-auth5.com",
                  ["Content-Type"] = type,
                },
              })
              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.same({ message = "No API key found in request" }, json)
            end)
          end
        end)
      end
    end)

    describe("key in headers", function()
      it("authenticates valid credentials", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "key-auth1.com",
            ["apikey"] = "kong"
          }
        })
        assert.res_status(200, res)
      end)
      it("returns 401 Unauthorized on invalid key", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]   = "key-auth1.com",
            ["apikey"] = "123"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "Invalid authentication credentials" }, json)
      end)
    end)

    describe("key in gRPC headers", function()
      it("rejects call without credentials", function()
        local ok, err = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {},
        }
        assert.falsy(ok)
        assert.matches("Code: Unauthenticated", err)
      end)
      it("accepts authorized calls", function()
        local ok, res = helpers.proxy_client_grpc(){
          service = "hello.HelloService.SayHello",
          opts = {
            ["-H"] = "'apikey: kong'",
          },
        }
        assert.truthy(ok)
        assert.same({ reply = "hello noname" }, cjson.decode(res))
      end)
    end)

    describe("underscores or hyphens in key headers", function()
      it("authenticates valid credentials", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "key-auth8.com",
            ["api_key"] = "kong"
          }
        })
        assert.res_status(200, res)

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "key-auth8.com",
            ["api-key"] = "kong"
          }
        })
        assert.res_status(200, res)
      end)

      it("returns 401 Unauthorized on invalid key", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]   = "key-auth8.com",
            ["api_key"] = "123"
          }
        })
        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "Invalid authentication credentials" }, json)

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"]   = "key-auth8.com",
            ["api-key"] = "123"
          }
        })
        body = assert.res_status(401, res)
        json = cjson.decode(body)
        assert.same({ message = "Invalid authentication credentials" }, json)
      end)
    end)

    describe("Consumer headers", function()
      it("sends Consumer headers to upstream", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            ["Host"] = "key-auth1.com",
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_string(json.headers["x-consumer-id"])
        assert.equal("bob", json.headers["x-consumer-username"])
        assert.equal(kong_cred.id, json.headers["x-credential-identifier"])
        assert.equal(nil, json.headers["x-credential-username"])
        assert.is_nil(json.headers["x-anonymous-consumer"])
      end)
    end)

    describe("config.hide_credentials", function()
      for _, content_type in pairs({
        "application/x-www-form-urlencoded",
        "application/json",
        "multipart/form-data",
      }) do

        local harness = {
          uri_args = { -- query string
            {
              headers = { Host = "key-auth1.com" },
              path    = "/request?apikey=kong",
              method  = "GET",
            },
            {
              headers = { Host = "key-auth2.com" },
              path    = "/request?apikey=kong",
              method  = "GET",
            }
          },
          headers = {
            {
              headers = { Host = "key-auth1.com", apikey = "kong" },
              path    = "/request",
              method  = "GET",
            },
            {
              headers = { Host = "key-auth2.com", apikey = "kong" },
              path    = "/request",
              method  = "GET",
            },
          },
          ["post_data.params"] = {
            {
              headers = { Host = "key-auth5.com" },
              body    = { apikey = "kong" },
              method  = "POST",
              path    = "/request",
            },
            {
              headers = { Host = "key-auth6.com" },
              body    = { apikey = "kong" },
              method  = "POST",
              path    = "/request",
            },
          }
        }

        for type, _ in pairs(harness) do
          describe(type, function()
            if type == "post_data.params" then
              harness[type][1].headers["Content-Type"] = content_type
              harness[type][2].headers["Content-Type"] = content_type
            end

            it("(" .. content_type .. ") false sends key to upstream", function()
              local res   = assert(proxy_client:send(harness[type][1]))
              local body  = assert.res_status(200, res)
              local json  = cjson.decode(body)
              local field = type == "post_data.params" and
                              json.post_data.params or
                              json[type]

              assert.equal("kong", field.apikey)
            end)

            it("(" .. content_type .. ") true doesn't send key to upstream", function()
              local res   = assert(proxy_client:send(harness[type][2]))
              local body  = assert.res_status(200, res)
              local json  = cjson.decode(body)
              local field = type == "post_data.params" and
                            json.post_data.params or
                            json[type]

              assert.is_nil(field.apikey)
            end)
          end)
        end

        it("(" .. content_type .. ") true preserves body MIME type", function()
          local res  = assert(proxy_client:send {
            method = "POST",
            path = "/request",
            headers = {
              Host = "key-auth6.com",
              ["Content-Type"] = content_type,
            },
            body = { apikey = "kong", foo = "bar" },
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("bar", json.post_data.params.foo)
        end)
      end

      it("fails with 'key_in_body' and unsupported content type", function()
        local res = assert(proxy_client:send {
          path = "/status/200",
          headers = {
            ["Host"] = "key-auth6.com",
            ["Content-Type"] = "text/plain",
          },
          body = "foobar",
        })

        local body = assert.res_status(401, res)
        local json = cjson.decode(body)
        assert.same({ message = "No API key found in request" }, json)
      end)
    end)

    describe("config.anonymous", function()
      it("works with right credentials and anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            ["Host"] = "key-auth3.com",
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal('bob', body.headers["x-consumer-username"])
        assert.equal(kong_cred.id, body.headers["x-credential-identifier"])
        assert.equal(nil, body.headers["x-credential-username"])
        assert.is_nil(body.headers["x-anonymous-consumer"])
      end)
      it("works with wrong credentials and anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "key-auth3.com"
          }
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal('true', body.headers["x-anonymous-consumer"])
        assert.equal(nil, body.headers["x-credential-identifier"])
        assert.equal(nil, body.headers["x-credential-username"])
        assert.equal('no-body', body.headers["x-consumer-username"])
      end)
      it("works with wrong credentials and username as anonymous", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "key-auth10.com"
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
            ["Host"] = "key-auth4.com"
          }
        })
        assert.response(res).has.status(500)
      end)
    end)
  end)


  describe("Plugin: key-auth (access) [#" .. strategy .. "]", function()
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
        "keyauth_credentials",
        "basicauth_credentials",
      })

      local route1 = bp.routes:insert {
        hosts = { "logical-and.com" },
      }

      local service = bp.services:insert {
        path = "/request",
      }

      local route2 = bp.routes:insert {
        hosts   = { "logical-or.com" },
        service = service,
      }

      bp.plugins:insert {
        name     = "basic-auth",
        route = { id = route1.id },
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route1.id },
      }

      anonymous = bp.consumers:insert {
        username = "Anonymous",
      }

      user1 = bp.consumers:insert {
        username = "Mickey",
      }

      user2 = bp.consumers:insert {
        username = "Aladdin",
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

      bp.keyauth_credentials:insert {
        key      = "Mouse",
        consumer = { id = user1.id },
      }

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
          method = "GET",
          path = "/request",
          headers = {
            ["Host"] = "logical-and.com",
            ["apikey"] = "Mouse",
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
            ["Host"]   = "logical-and.com",
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
            ["Host"]          = "logical-and.com",
            ["Authorization"] = "Basic QWxhZGRpbjpPcGVuU2VzYW1l",
          }
        })
        assert.response(res).has.status(401)
      end)

      it("fails 401, with no credential provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"] = "logical-and.com",
          }
        })
        assert.response(res).has.status(401)
      end)

    end)

    describe("multiple auth with anonymous, logical OR", function()
      it("passes with all credentials provided", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]          = "logical-or.com",
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
            ["Host"]   = "logical-or.com",
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
            ["Host"]          = "logical-or.com",
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
            ["Host"] = "logical-or.com",
          }
        })
        assert.response(res).has.status(200)
        assert.request(res).has.header("x-anonymous-consumer")
        local id = assert.request(res).has.header("x-consumer-id")
        assert.equal(id, anonymous.id)
      end)

    end)

    describe("auto-expiring keys", function()
      -- Give a bit of time to reduce test flakyness on slow setups
      local ttl = 4
      local inserted_at

      lazy_setup(function()
        helpers.stop_kong()

        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
          "consumers",
          "keyauth_credentials",
        })

        local r = bp.routes:insert {
          hosts = { "key-ttl.com" },
        }

        bp.plugins:insert {
          name = "key-auth",
          route = { id = r.id },
        }

        local user_jafar = bp.consumers:insert {
          username = "Jafar",
        }

        bp.keyauth_credentials:insert({
          key = "kong",
          consumer = { id = user_jafar.id },
        }, { ttl = ttl })

        inserted_at = ngx.now()

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

      it("authenticate for up to 'ttl'", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "key-ttl.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(200, res)

        ngx.update_time()
        local elapsed = ngx.now() - inserted_at
        ngx.sleep(ttl - elapsed + 1) -- 1: jitter

        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            ["Host"] = "key-ttl.com",
            ["apikey"] = "kong",
          }
        })
        assert.res_status(401, res)
      end)
    end)
  end)
end


for _, strategy in helpers.each_strategy() do
  describe("Plugin: key-auth (access) [#" .. strategy .. "]", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local consumer = bp.consumers:insert({ username = "bob" })
      bp.keyauth_credentials:insert({ key = "right", consumer = { id = consumer.id } })
      local service = bp.services:insert({ path = "/status/200" })

      local r1 = bp.routes:insert({ paths = { "/ttt" }, service = service })
      local r2 = bp.routes:insert({ paths = { "/ttf" }, service = service })
      local r3 = bp.routes:insert({ paths = { "/tff" }, service = service })
      local r4 = bp.routes:insert({ paths = { "/fff" }, service = service })
      local r5 = bp.routes:insert({ paths = { "/fft" }, service = service })
      local r6 = bp.routes:insert({ paths = { "/tft" }, service = service })
      local r7 = bp.routes:insert({ paths = { "/ftf" }, service = service })

      bp.plugins:insert({ name = "key-auth", route = r1, config = {
        key_in_header = true,  key_in_query = true,  key_in_body = true }
                        })
      bp.plugins:insert({ name = "key-auth", route = r2, config = {
        key_in_header = true,  key_in_query = true,  key_in_body = false }
                        })
      bp.plugins:insert({ name = "key-auth", route = r3, config = {
        key_in_header = true,  key_in_query = false, key_in_body = false }
                        })
      bp.plugins:insert({ name = "key-auth", route = r4, config = {
        key_in_header = false, key_in_query = false, key_in_body = false
      }})
      bp.plugins:insert({ name = "key-auth", route = r5, config = {
        key_in_header = false, key_in_query = false, key_in_body = true
      }})
      bp.plugins:insert({ name = "key-auth", route = r6, config = {
        key_in_header = true, key_in_query = false, key_in_body = true
      }})
      bp.plugins:insert({ name = "key-auth", route = r7, config = {
        key_in_header = false, key_in_query = true, key_in_body = false
      }})

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    local tests = {
      ---header--query----body-----path----res---
      { "right", "right", "right", "/ttt", 200 }, -- 1
      { "right", "right", "right", "/ttf", 200 },
      { "right", "right", "right", "/tff", 200 },
      { "right", "right", "right", "/fff", 401 },
      { "right", "right", "right", "/fft", 200 },
      { "right", "right", "right", "/tft", 200 },
      { "right", "right", "right", "/ftf", 200 },
      { "right", "right", "wrong", "/ttt", 200 }, -- 8
      { "right", "right", "wrong", "/ttf", 200 },
      { "right", "right", "wrong", "/tff", 200 },
      { "right", "right", "wrong", "/fff", 401 },
      { "right", "right", "wrong", "/fft", 401 },
      { "right", "right", "wrong", "/tft", 200 },
      { "right", "right", "wrong", "/ftf", 200 },
      { "right", "wrong", "wrong", "/ttt", 200 }, -- 15
      { "right", "wrong", "wrong", "/ttf", 200 },
      { "right", "wrong", "wrong", "/tff", 200 },
      { "right", "wrong", "wrong", "/fff", 401 },
      { "right", "wrong", "wrong", "/fft", 401 },
      { "right", "wrong", "wrong", "/tft", 200 },
      { "right", "wrong", "wrong", "/ftf", 401 },
      { "wrong", "wrong", "wrong", "/ttt", 401 }, -- 22
      { "wrong", "wrong", "wrong", "/ttf", 401 },
      { "wrong", "wrong", "wrong", "/tff", 401 },
      { "wrong", "wrong", "wrong", "/fff", 401 },
      { "wrong", "wrong", "wrong", "/fft", 401 },
      { "wrong", "wrong", "wrong", "/tft", 401 },
      { "wrong", "wrong", "wrong", "/ftf", 401 },
      { "wrong", "wrong", "right", "/ttt", 401 }, -- 29
      { "wrong", "wrong", "right", "/ttf", 401 },
      { "wrong", "wrong", "right", "/tff", 401 },
      { "wrong", "wrong", "right", "/fff", 401 },
      { "wrong", "wrong", "right", "/fft", 200 },
      { "wrong", "wrong", "right", "/tft", 401 },
      { "wrong", "wrong", "right", "/ftf", 401 },
      { "right", "wrong", "right", "/ttt", 200 }, -- 36
      { "right", "wrong", "right", "/ttf", 200 },
      { "right", "wrong", "right", "/tff", 200 },
      { "right", "wrong", "right", "/fff", 401 },
      { "right", "wrong", "right", "/fft", 200 },
      { "right", "wrong", "right", "/tft", 200 },
      { "right", "wrong", "right", "/ftf", 401 },
      { "wrong", "right", "wrong", "/ttt", 401 }, -- 43
      { "wrong", "right", "wrong", "/ttf", 401 },
      { "wrong", "right", "wrong", "/tff", 401 },
      { "wrong", "right", "wrong", "/fff", 401 },
      { "wrong", "right", "wrong", "/fft", 401 },
      { "wrong", "right", "wrong", "/tft", 401 },
      { "wrong", "right", "wrong", "/ftf", 200 },
      { nil,     nil,     nil,     "/ttt", 401 }, -- 50
      { nil,     nil,     nil,     "/ttf", 401 },
      { nil,     nil,     nil,     "/tff", 401 },
      { nil,     nil,     nil,     "/fff", 401 },
      { nil,     nil,     nil,     "/fft", 401 },
      { nil,     nil,     nil,     "/tft", 401 },
      { nil,     nil,     nil,     "/ftf", 401 },
      { nil,     nil,     "wrong", "/ttt", 401 }, -- 57
      { nil,     nil,     "wrong", "/ttf", 401 },
      { nil,     nil,     "wrong", "/tff", 401 },
      { nil,     nil,     "wrong", "/fff", 401 },
      { nil,     nil,     "wrong", "/fft", 401 },
      { nil,     nil,     "wrong", "/tft", 401 },
      { nil,     nil,     "wrong", "/ftf", 401 },
      { nil,     "wrong", "wrong", "/ttt", 401 }, -- 64
      { nil,     "wrong", "wrong", "/ttf", 401 },
      { nil,     "wrong", "wrong", "/tff", 401 },
      { nil,     "wrong", "wrong", "/fff", 401 },
      { nil,     "wrong", "wrong", "/fft", 401 },
      { nil,     "wrong", "wrong", "/tft", 401 },
      { nil,     "wrong", "wrong", "/ftf", 401 },
      { "wrong", "wrong", nil,     "/ttt", 401 }, -- 71
      { "wrong", "wrong", nil,     "/ttf", 401 },
      { "wrong", "wrong", nil,     "/tff", 401 },
      { "wrong", "wrong", nil,     "/fff", 401 },
      { "wrong", "wrong", nil,     "/fft", 401 },
      { "wrong", "wrong", nil,     "/tft", 401 },
      { "wrong", "wrong", nil,     "/ftf", 401 },
      { nil,     "wrong", nil,     "/ttt", 401 }, -- 78
      { nil,     "wrong", nil,     "/ttf", 401 },
      { nil,     "wrong", nil,     "/tff", 401 },
      { nil,     "wrong", nil,     "/fff", 401 },
      { nil,     "wrong", nil,     "/fft", 401 },
      { nil,     "wrong", nil,     "/tft", 401 },
      { nil,     "wrong", nil,     "/ftf", 401 },
      { "wrong", nil,     "wrong", "/ttt", 401 }, -- 85
      { "wrong", nil,     "wrong", "/ttf", 401 },
      { "wrong", nil,     "wrong", "/tff", 401 },
      { "wrong", nil,     "wrong", "/fff", 401 },
      { "wrong", nil,     "wrong", "/fft", 401 },
      { "wrong", nil,     "wrong", "/tft", 401 },
      { "wrong", nil,     "wrong", "/ftf", 401 },
      { "right", "right", nil,     "/ttt", 200 }, -- 92
      { "right", "right", nil,     "/ttf", 200 },
      { "right", "right", nil,     "/tff", 200 },
      { "right", "right", nil,     "/fff", 401 },
      { "right", "right", nil,     "/fft", 401 },
      { "right", "right", nil,     "/tft", 200 },
      { "right", "right", nil,     "/ftf", 200 },
      { "right", nil,     nil,     "/ttt", 200 }, -- 99
      { "right", nil,     nil,     "/ttf", 200 },
      { "right", nil,     nil,     "/tff", 200 },
      { "right", nil,     nil,     "/fff", 401 },
      { "right", nil,     nil,     "/fft", 401 },
      { "right", nil,     nil,     "/tft", 200 },
      { "right", nil,     nil,     "/ftf", 401 },
      { nil,     nil,     "right", "/ttt", 200 }, -- 106
      { nil,     nil,     "right", "/ttf", 401 },
      { nil,     nil,     "right", "/tff", 401 },
      { nil,     nil,     "right", "/fff", 401 },
      { nil,     nil,     "right", "/fft", 200 },
      { nil,     nil,     "right", "/tft", 200 },
      { nil,     nil,     "right", "/ftf", 401 },
      { "right", nil,     "right", "/ttt", 200 }, -- 113
      { "right", nil,     "right", "/ttf", 200 },
      { "right", nil,     "right", "/tff", 200 },
      { "right", nil,     "right", "/fff", 401 },
      { "right", nil,     "right", "/fft", 200 },
      { "right", nil,     "right", "/tft", 200 },
      { "right", nil,     "right", "/ftf", 401 },
      { nil,     "right", nil,     "/ttt", 200 }, -- 120
      { nil,     "right", nil,     "/ttf", 200 },
      { nil,     "right", nil,     "/tff", 401 },
      { nil,     "right", nil,     "/fff", 401 },
      { nil,     "right", nil,     "/fft", 401 },
      { nil,     "right", nil,     "/tft", 401 },
      { nil,     "right", nil,     "/ftf", 200 },
      { nil,     "right", "wrong", "/ttt", 200 }, -- 127
      { nil,     "right", "wrong", "/ttf", 200 },
      { nil,     "right", "wrong", "/tff", 401 },
      { nil,     "right", "wrong", "/fff", 401 },
      { nil,     "right", "wrong", "/fft", 401 },
      { nil,     "right", "wrong", "/tft", 401 },
      { nil,     "right", "wrong", "/ftf", 200 },
      { "right", "wrong", nil,     "/ttt", 200 }, -- 134
      { "right", "wrong", nil,     "/ttf", 200 },
      { "right", "wrong", nil,     "/tff", 200 },
      { "right", "wrong", nil,     "/fff", 401 },
      { "right", "wrong", nil,     "/fft", 401 },
      { "right", "wrong", nil,     "/tft", 200 },
      { "right", "wrong", nil,     "/ftf", 401 },
      { "right", nil,     "wrong", "/ttt", 200 }, -- 141
      { "right", nil,     "wrong", "/ttf", 200 },
      { "right", nil,     "wrong", "/tff", 200 },
      { "right", nil,     "wrong", "/fff", 401 },
      { "right", nil,     "wrong", "/fft", 401 },
      { "right", nil,     "wrong", "/tft", 200 },
      { "right", nil,     "wrong", "/ftf", 401 },
      { nil,     "wrong", "right", "/ttt", 401 }, -- 148
      { nil,     "wrong", "right", "/ttf", 401 },
      { nil,     "wrong", "right", "/tff", 401 },
      { nil,     "wrong", "right", "/fff", 401 },
      { nil,     "wrong", "right", "/fft", 200 },
      { nil,     "wrong", "right", "/tft", 200 },
      { nil,     "wrong", "right", "/ftf", 401 },
      { "wrong", "right", nil,     "/ttt", 401 }, -- 155
      { "wrong", "right", nil,     "/ttf", 401 },
      { "wrong", "right", nil,     "/tff", 401 },
      { "wrong", "right", nil,     "/fff", 401 },
      { "wrong", "right", nil,     "/fft", 401 },
      { "wrong", "right", nil,     "/tft", 401 },
      { "wrong", "right", nil,     "/ftf", 200 },
      { "wrong", nil,     "right", "/ttt", 401 }, -- 162
      { "wrong", nil,     "right", "/ttf", 401 },
      { "wrong", nil,     "right", "/tff", 401 },
      { "wrong", nil,     "right", "/fff", 401 },
      { "wrong", nil,     "right", "/fft", 200 },
      { "wrong", nil,     "right", "/tft", 401 },
      { "wrong", nil,     "right", "/ftf", 401 },
    }

    for i, test in ipairs(tests) do
      local header = test[1]
      local query = ""
      if test[2] then
        query = "?apikey=" .. test[2]
      end

      local body
      if test[3] then
        body = "apikey=" .. test[3]
      end

      local path = test[4]

      local input = string.sub(test[1] or "n", 1, 1) ..
                    string.sub(test[2] or "n", 1, 1) ..
                    string.sub(test[3] or "n", 1, 1)

      it("combination #" .. i .. " (" .. input .. " => " .. string.sub(path, 2) .. ") works", function()
        local proxy_client = helpers.proxy_client()
        local res = proxy_client:post(path .. query, {
          body = body,
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["apikey"] = header,
          },
        })
        assert.res_status(test[5], res)
        proxy_client:close()
      end)
    end
  end)
end
