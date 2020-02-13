local helpers = require "spec.helpers"
local cjson   = require "cjson"
local meta    = require "kong.meta"
local utils   = require "kong.tools.utils"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: key-auth (access) [#" .. strategy .. "]", function()
    local proxy_client

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

      bp.keyauth_credentials:insert {
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
        assert.equal([[{"message":"No API key found in request"}]], body)
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

        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ message = "Cannot process request body" }, json)
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
