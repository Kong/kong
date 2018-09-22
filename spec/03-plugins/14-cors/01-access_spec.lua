local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: cors (access) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local route1 = bp.routes:insert({
        hosts = { "cors1.com" },
      })

      local route2 = bp.routes:insert({
        hosts = { "cors2.com" },
      })

      local route3 = bp.routes:insert({
        hosts = { "cors3.com" },
      })

      local route4 = bp.routes:insert({
        hosts = { "cors4.com" },
      })

      local route5 = bp.routes:insert({
        hosts = { "cors5.com" },
      })

      local route6 = bp.routes:insert({
        hosts = { "cors6.com" },
      })

      local route7 = bp.routes:insert({
        hosts = { "cors7.com" },
      })

      local route8 = bp.routes:insert({
        hosts = { "cors-empty-origins.com" },
      })

      local route9 = bp.routes:insert({
        hosts = { "cors9.com" },
      })

      bp.plugins:insert {
        name     = "cors",
        route_id = route1.id,
      }

      bp.plugins:insert {
        name     = "cors",
        route_id = route2.id,
        config   = {
          origins         = { "example.com" },
          methods         = { "GET" },
          headers         = { "origin", "type", "accepts" },
          exposed_headers = { "x-auth-token" },
          max_age         = 23,
          credentials     = true
        }
      }

      bp.plugins:insert {
        name     = "cors",
        route_id = route3.id,
        config   = {
          origins            = { "example.com" },
          methods            = { "GET" },
          headers            = { "origin", "type", "accepts" },
          exposed_headers    = { "x-auth-token" },
          max_age            = 23,
          preflight_continue = true
        }
      }

      bp.plugins:insert {
        name     = "cors",
        route_id = route4.id,
      }

      bp.plugins:insert {
        name     = "key-auth",
        route_id = route4.id
      }

      bp.plugins:insert {
        name     = "cors",
        route_id = route5.id,
        config   = {
          origins     = { "*" },
          credentials = true
        }
      }

      bp.plugins:insert {
        name     = "cors",
        route_id = route6.id,
        config   = {
          origins            = { "example.com", "example.org" },
          methods            = { "GET" },
          headers            = { "origin", "type", "accepts" },
          exposed_headers    = { "x-auth-token" },
          max_age            = 23,
          preflight_continue = true
        }
      }

      bp.plugins:insert {
        name     = "cors",
        route_id = route7.id,
        config   = {
          origins     = { "*" },
          credentials = false
        }
      }

      bp.plugins:insert {
        name     = "cors",
        route_id = route8.id,
        config   = {
          origins = {},
        }
      }

      bp.plugins:insert {
        name     = "cors",
        route_id = route9.id,
        config   = {
          origins = { [[.*\.?example(?:-foo)?.com]] },
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    teardown(function()
      if proxy_client then proxy_client:close() end
      helpers.stop_kong()
    end)

    describe("HTTP method: OPTIONS", function()
      it("gives appropriate defaults", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors1.com"
          }
        })
        assert.res_status(204, res)
        assert.equal("GET,HEAD,PUT,PATCH,POST,DELETE", res.headers["Access-Control-Allow-Methods"])
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("gives * wildcard when origins is empty", function()
        -- this test covers a regression introduced in 0.10.1, where
        -- the 'multiple_origins' migration would always insert a table
        -- (that might be empty) in the 'config.origins' field, and the
        -- * wildcard would only been sent when said table was **nil**,
        -- and not necessarily empty.

        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors-empty-origins.com",
          }
        })
        assert.res_status(204, res)
        assert.equal("GET,HEAD,PUT,PATCH,POST,DELETE", res.headers["Access-Control-Allow-Methods"])
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("gives appropriate defaults when origin is explicitly set to *", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors5.com"
          }
        })
        assert.res_status(204, res)
        assert.equal("GET,HEAD,PUT,PATCH,POST,DELETE", res.headers["Access-Control-Allow-Methods"])
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("accepts config options", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors2.com"
          }
        })
        assert.res_status(204, res)
        assert.equal("GET", res.headers["Access-Control-Allow-Methods"])
        assert.equal("example.com", res.headers["Access-Control-Allow-Origin"])
        assert.equal("23", res.headers["Access-Control-Max-Age"])
        assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("origin,type,accepts", res.headers["Access-Control-Allow-Headers"])
        assert.equal("Origin", res.headers["Vary"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
      end)

      it("preflight_continue enabled", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          path    = "/status/201",
          headers = {
            ["Host"] = "cors3.com"
          }
        })
        local body = assert.res_status(201, res)
        local json = cjson.decode(body)
        assert.equal(201, json.code)
      end)

      it("replies with request-headers if present in request", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"]                           = "cors5.com",
            ["Access-Control-Request-Headers"] = "origin,accepts",
          }
        })

        assert.res_status(204, res)
        assert.equal("origin,accepts", res.headers["Access-Control-Allow-Headers"])
      end)
    end)

    describe("HTTP method: others", function()
      it("gives appropriate defaults", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "cors1.com"
          }
        })
        assert.res_status(200, res)
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("accepts config options", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "cors2.com"
          }
        })
        assert.res_status(200, res)
        assert.equal("example.com", res.headers["Access-Control-Allow-Origin"])
        assert.equal("x-auth-token", res.headers["Access-Control-Expose-Headers"])
        assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("Origin", res.headers["Vary"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("works with 404 responses", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/asdasdasd",
          headers = {
            ["Host"] = "cors1.com"
          }
        })
        assert.res_status(404, res)
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("works with 40x responses returned by another plugin", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "cors4.com"
          }
        })
        assert.res_status(401, res)
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("sets CORS orgin based on origin host", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors6.com",
            ["Origin"] = "http://www.example.com"
          }
        })
        assert.res_status(200, res)
        assert.equal("http://www.example.com", res.headers["Access-Control-Allow-Origin"])

        local domains = {
          ["example.com"]         = true,
          ["www.example.com"]     = true,
          ["example-foo.com"]     = true,
          ["www.example-foo.com"] = true,
          ["www.example-fo0.com"] = false,
        }

        for domain in pairs(domains) do
          local res = assert(proxy_client:send {
            method  = "GET",
            headers = {
              ["Host"]   = "cors9.com",
              ["Origin"] = domain
            }
          })
          assert.res_status(200, res)
          assert.equal(domains[domain] and domain or nil,
                       res.headers["Access-Control-Allow-Origin"])
        end
      end)

      it("does not sets CORS orgin if origin host is not in origin_domains list", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors6.com",
            ["Origin"] = "http://www.example.net"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["Access-Control-Allow-Origin"])
      end)

      it("responds with the requested Origin when config.credentials=true", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors5.com",
            ["Origin"] = "http://www.example.net"
          }
        })
        assert.res_status(200, res)
        assert.equals("http://www.example.net", res.headers["Access-Control-Allow-Origin"])
        assert.equals("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("Origin", res.headers["Vary"])
      end)

      it("responds with the requested Origin (including port) when config.credentials=true", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors5.com",
            ["Origin"] = "http://www.example.net:3000"
          }
        })
        assert.res_status(200, res)
        assert.equals("http://www.example.net:3000", res.headers["Access-Control-Allow-Origin"])
        assert.equals("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("Origin", res.headers["Vary"])
      end)

      it("responds with * when config.credentials=false", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors7.com",
            ["Origin"] = "http://www.example.net"
          }
        })
        assert.res_status(200, res)
        assert.equals("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
      end)
    end)
  end)
end
