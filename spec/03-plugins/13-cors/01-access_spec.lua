local helpers = require "spec.helpers"
local cjson = require "cjson"
local inspect = require "inspect"
local tablex = require "pl.tablex"


local CORS_DEFAULT_METHODS = "GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS,TRACE,CONNECT"


local function sortedpairs(t)
  local ks = tablex.keys(t)
  table.sort(ks)
  local i = 0
  return function()
    i = i + 1
    return ks[i], t[ks[i]]
  end
end


for _, strategy in helpers.each_strategy() do
  describe("Plugin: cors (access) [#" .. strategy .. "]", function()
    local proxy_client

    local regex_testcases = {
      {
        -- single entry, host only: ignore value, always return configured data
        origins = { "foo.test" },
        tests = {
          ["http://evil.test"]          = "foo.test",
          ["http://foo.test"]           = "foo.test",
          ["http://foo.test.evil.test"] = "foo.test",
          ["http://something.foo.test"] = "foo.test",
          ["http://evilfoo.test"]       = "foo.test",
          ["http://foo.test:80"]        = "foo.test",
          ["http://foo.test:8000"]      = "foo.test",
          ["https://foo.test:8000"]     = "foo.test",
          ["http://foo.test:90"]        = "foo.test",
          ["http://foobtest"]           = "foo.test",
          ["https://bar.test:1234"]     = "foo.test",
        },
      },
      {
        -- single entry, full domain (not regex): ignore value, always return configured data
        origins = { "https://bar.test:1234" },
        tests = {
          ["http://evil.test"]          = "https://bar.test:1234",
          ["http://foo.test"]           = "https://bar.test:1234",
          ["http://foo.test.evil.test"] = "https://bar.test:1234",
          ["http://something.foo.test"] = "https://bar.test:1234",
          ["http://evilfoo.test"]       = "https://bar.test:1234",
          ["http://foo.test:80"]        = "https://bar.test:1234",
          ["http://foo.test:8000"]      = "https://bar.test:1234",
          ["https://foo.test:8000"]     = "https://bar.test:1234",
          ["http://foo.test:90"]        = "https://bar.test:1234",
          ["http://foobtest"]           = "https://bar.test:1234",
          ["https://bar.test:1234"]     = "https://bar.test:1234",
        },
      },
      {
        -- single entry, simple regex without ":": anchored match on host only
        origins = { "foo\\.test" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = true,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = false,
          ["http://evilfoo.test"]       = false,
          ["http://foo.test:80"]        = "http://foo.test",
          ["http://foo.test:8000"]      = true,
          ["https://foo.test:8000"]     = true,
          ["http://foo.test:90"]        = true,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- single entry, subdomain regex without ":": anchored match on host only
        origins = { "(.*[./])?foo\\.test" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = true,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = true,
          ["http://evilfoo.test"]       = false,
          ["http://foo.test:80"]        = "http://foo.test",
          ["http://foo.test:8000"]      = true,
          ["https://foo.test:8000"]     = true,
          ["http://foo.test:90"]        = true,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- single entry, any-scheme subdomain regex with port: anchored match with scheme and port
        origins = { "(.*[./])?foo\\.test:8000" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = false,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = false,
          ["http://evilfoo.test"]       = false,
          ["http://foo.test:80"]        = false,
          ["http://foo.test:8000"]      = true,
          ["https://foo.test:8000"]     = true,
          ["http://foo.test:90"]        = false,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- single entry, https subdomain regex with port: anchored match with scheme and port
        origins = { "https://(.*[.])?foo\\.test:8000" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = false,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = false,
          ["http://foo.test:80"]        = false,
          ["http://foo.test:8000"]      = false,
          ["https://foo.test:8000"]     = true,
          ["http://foo.test:90"]        = false,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- single entry, explicitly anchored https subdomain regex with port: anchored match with scheme and port
        origins = { "^http://(.*[.])?foo\\.test(:(80|90))?$" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = true,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = true,
          ["http://foo.test:80"]        = "http://foo.test",
          ["http://foo.test:8000"]      = false,
          ["https://foo.test:8000"]     = false,
          ["http://foo.test:90"]        = true,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- multiple entries, host only (not regex): match on full normalized domain (i.e. all fail)
        origins = { "foo.test", "bar.test" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = false,
          ["http://foo.test.evil.test"] = false,
          ["http://foo.test:80"]        = false,
          ["http://foo.test:8000"]      = false,
          ["http://foo.test:90"]        = false,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- multiple entries, full domain (not regex): match on full normalized domain
        origins = { "http://foo.test", "https://bar.test:1234" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = true,
          ["http://foo.test.evil.test"] = false,
          ["http://foo.test:80"]        = "http://foo.test",
          ["http://foo.test:8000"]      = false,
          ["http://foo.test:90"]        = false,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = true,
        },
      },
      {
        -- multiple entries, simple regex without ":": anchored match on host only
        origins = { "bar.test", "foo\\.test" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = true,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = false,
          ["http://foo.test:80"]        = "http://foo.test",
          ["http://foo.test:8000"]      = true,
          ["http://foo.test:90"]        = true,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- multiple entries, subdomain regex without ":": anchored match on host only
        origins = { "bar.test", "(.*\\.)?foo\\.test" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = true,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = true,
          ["http://foo.test:80"]        = "http://foo.test",
          ["http://foo.test:8000"]      = true,
          ["http://foo.test:90"]        = true,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- multiple entries, any-scheme subdomain regex with ":": anchored match with scheme and port
        origins = { "bar.test", "(.*[./])?foo\\.test:8000" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = false,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = false,
          ["http://foo.test:80"]        = false,
          ["http://foo.test:8000"]      = true,
          ["https://foo.test:8000"]     = true,
          ["http://foo.test:90"]        = false,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
      {
        -- multiple entries, https subdomain regex with ":": anchored match with scheme and port
        origins = { "bar.test", "https://(.*\\.)?foo\\.test:8000" },
        tests = {
          ["http://evil.test"]          = false,
          ["http://foo.test"]           = false,
          ["http://foo.test.evil.test"] = false,
          ["http://something.foo.test"] = false,
          ["http://foo.test:80"]        = false,
          ["http://foo.test:8000"]      = false,
          ["https://foo.test:8000"]     = true,
          ["http://foo.test:90"]        = false,
          ["http://foobtest"]           = false,
          ["https://bar.test:1234"]     = false,
        },
      },
    }

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, nil, { "error-generator-last" })

      local route1 = bp.routes:insert({
        hosts = { "cors1.test" },
      })

      local route2 = bp.routes:insert({
        hosts = { "cors2.test" },
      })

      local route3 = bp.routes:insert({
        hosts = { "cors3.test" },
      })

      local route4 = bp.routes:insert({
        hosts = { "cors4.test" },
      })

      local route5 = bp.routes:insert({
        hosts = { "cors5.test" },
      })

      local route6 = bp.routes:insert({
        hosts = { "cors6.test" },
      })

      local route7 = bp.routes:insert({
        hosts = { "cors7.test" },
      })

      local route8 = bp.routes:insert({
        hosts = { "cors-empty-origins.test" },
      })

      local route9 = bp.routes:insert({
        hosts = { "cors9.test" },
      })

      local route10 = bp.routes:insert({
        hosts = { "cors10.test" },
      })

      local route11 = bp.routes:insert({
        hosts = { "cors11.test" },
      })

      local route12 = bp.routes:insert({
        hosts = { "cors12.test" },
      })

      local route13 = bp.routes:insert({
        hosts = { "cors13.test" },
      })

      local mock_upstream = bp.services:insert {
        host = helpers.mock_upstream_hostname,
        port = helpers.mock_upstream_port,
      }

      local route_upstream = bp.routes:insert({
        hosts = { "cors-upstream.test" },
        service = mock_upstream
      })

      local mock_service = bp.services:insert {
        host = "127.0.0.2",
        port = 26865,
      }

      local route_timeout = bp.routes:insert {
        hosts = { "cors-timeout.test" },
        service = mock_service,
      }

      local route_error = bp.routes:insert {
        hosts = { "cors-error.test" },
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route1.id },
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route2.id },
        config = {
          origins         = { "example.test" },
          methods         = { "GET" },
          headers         = { "origin", "type", "accepts" },
          exposed_headers = { "x-auth-token" },
          max_age         = 23,
          credentials     = true
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route3.id },
        config = {
          origins            = { "example.test" },
          methods            = { "GET" },
          headers            = { "origin", "type", "accepts" },
          exposed_headers    = { "x-auth-token" },
          max_age            = 23,
          preflight_continue = true
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route4.id },
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = route4.id }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route5.id },
        config = {
          origins     = { "*" },
          credentials = true
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route6.id },
        config = {
          origins            = { "example.test", "example.org" },
          methods            = { "GET" },
          headers            = { "origin", "type", "accepts" },
          exposed_headers    = { "x-auth-token" },
          max_age            = 23,
          preflight_continue = true
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route7.id },
        config = {
          origins     = { "*" },
          credentials = false
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route8.id },
        config = {
          origins = {},
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route9.id },
        config = {
          origins = { [[.*\.?example(?:-foo)?.test]] },
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route10.id },
        config = {
          origins = { "http://my-site.test", "http://my-other-site.test" },
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route11.id },
        config = {
          origins = { "http://my-site.test", "https://my-other-site.test:9000" },
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route12.id },
        config = {
          credentials = true,
          preflight_continue = false,
          max_age = 1728000,
          headers = {
            "DNT",
            "X-CustomHeader",
            "Keep-Alive",
            "User-Agent",
            "X-Requested-With",
            "If-Modified-Since",
            "Cache-Control",
            "Content-Type",
            "Authorization"
          },
          methods = ngx.null,
          origins = {
            "a.xxx.test",
            "allowed-domain.test"
          },
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route13.id },
        config = {
          preflight_continue = false,
          private_network = true,
          origins = { 'allowed-domain.test' }
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route_timeout.id },
        config = {
          origins            = { "example.test" },
          methods            = { "GET" },
          headers            = { "origin", "type", "accepts" },
          exposed_headers    = { "x-auth-token" },
          max_age            = 10,
          preflight_continue = true
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route_error.id },
        config = {
          origins            = { "example.test" },
          methods            = { "GET" },
          headers            = { "origin", "type", "accepts" },
          exposed_headers    = { "x-auth-token" },
          max_age            = 10,
          preflight_continue = true
        }
      }

      bp.plugins:insert {
        name = "cors",
        route = { id = route_upstream.id },
        config = {
          origins            = { "example.test" },
          methods            = { "GET" },
          headers            = { "origin", "type", "accepts" },
          exposed_headers    = { "x-auth-token" },
          max_age            = 10,
          preflight_continue = true
        }
      }


      bp.plugins:insert {
        name = "error-generator-last",
        route = { id = route_error.id },
        config = {
          access = true,
        },
      }

      for i, testcase in ipairs(regex_testcases) do
        local route = bp.routes:insert({
          hosts = { "cors-regex-" .. i .. ".test" },
        })

        bp.plugins:insert {
          name = "cors",
          route = { id = route.id },
          config = {
            origins = testcase.origins,
          }
        }
      end

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    describe("HTTP method: OPTIONS", function()

      for i, testcase in ipairs(regex_testcases) do
        local host = "cors-regex-" .. i .. ".test"
        for origin, accept in sortedpairs(testcase.tests) do
          it("given " .. origin .. ", " ..
             inspect(testcase.origins) .. " will " ..
             (accept and "accept" or "reject"), function()

            local res = assert(proxy_client:send {
              method  = "OPTIONS",
              headers = {
                ["Host"] = host,
                ["Origin"] = origin,
                ["Access-Control-Request-Method"] = "GET",
              }
            })

            assert.res_status(200, res)

            if accept then
              assert.equal(CORS_DEFAULT_METHODS, res.headers["Access-Control-Allow-Methods"])
              assert.equal(accept == true and origin or accept, res.headers["Access-Control-Allow-Origin"])
              assert.is_nil(res.headers["Access-Control-Allow-Headers"])
              assert.is_nil(res.headers["Access-Control-Expose-Headers"])
              assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
              assert.is_nil(res.headers["Access-Control-Max-Age"])

            else
              assert.is_nil(res.headers["Access-Control-Allow-Origin"])
            end
          end)
        end
      end

      it("gives appropriate defaults", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors1.test",
            ["Origin"] = "origin1.test",
            ["Access-Control-Request-Method"] = "GET",
          }
        })
        assert.res_status(200, res)
        assert.equal("0", res.headers["Content-Length"])
        assert.equal(CORS_DEFAULT_METHODS, res.headers["Access-Control-Allow-Methods"])
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
        assert.is_nil(res.headers["Vary"])
      end)

      it("gives * wildcard when config.origins is empty", function()
        -- this test covers a regression introduced in 0.10.1, where
        -- the 'multiple_origins' migration would always insert a table
        -- (that might be empty) in the 'config.origins' field, and the
        -- * wildcard would only been sent when said table was **nil**,
        -- and not necessarily empty.

        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors-empty-origins.test",
            ["Origin"] = "empty-origin.test",
            ["Access-Control-Request-Method"] = "GET",
          }
        })
        assert.res_status(200, res)
        assert.equal("0", res.headers["Content-Length"])
        assert.equal(CORS_DEFAULT_METHODS, res.headers["Access-Control-Allow-Methods"])
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
        assert.is_nil(res.headers["Vary"])
      end)

      it("gives appropriate defaults when origin is explicitly set to *", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors5.test",
            ["Origin"] = "origin5.test",
            ["Access-Control-Request-Method"] = "GET",
          }
        })
        assert.res_status(200, res)
        assert.equal("0", res.headers["Content-Length"])
        assert.equal(CORS_DEFAULT_METHODS, res.headers["Access-Control-Allow-Methods"])
        assert.equal("origin5.test", res.headers["Access-Control-Allow-Origin"])
        assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("Origin", res.headers["Vary"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("accepts config options", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"] = "cors2.test",
            ["Origin"] = "origin5.test",
            ["Access-Control-Request-Method"] = "GET",
          }
        })
        assert.res_status(200, res)
        assert.equal("0", res.headers["Content-Length"])
        assert.equal("GET", res.headers["Access-Control-Allow-Methods"])
        assert.equal("example.test", res.headers["Access-Control-Allow-Origin"])
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
            ["Host"] = "cors3.test"
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
            ["Host"]                           = "cors5.test",
            ["Origin"]                         = "origin5.test",
            ["Access-Control-Request-Headers"] = "origin,accepts",
            ["Access-Control-Request-Method"]  = "GET",
          }
        })

        assert.res_status(200, res)
        assert.equal("0", res.headers["Content-Length"])
        assert.equal("origin,accepts", res.headers["Access-Control-Allow-Headers"])
      end)

      it("properly validates flat strings", function()
        -- Legitimate origins
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"]   = "cors10.test",
            ["Origin"] = "http://my-site.test"
          }
        })

        assert.res_status(200, res)
        assert.equal("http://my-site.test", res.headers["Access-Control-Allow-Origin"])

        -- Illegitimate origins
        res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"]   = "cors10.test",
            ["Origin"] = "http://bad-guys.test"
          }
        })

        assert.res_status(200, res)
        assert.is_nil(res.headers["Access-Control-Allow-Origin"])

        -- Tricky illegitimate origins
        res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"]   = "cors10.test",
            ["Origin"] = "http://my-site.test.bad-guys.test"
          }
        })

        assert.res_status(200, res)
        assert.is_nil(res.headers["Access-Control-Allow-Origin"])
      end)

      it("support private-network", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          headers = {
            ["Host"]   = "cors13.test",
            ["Origin"] = "allowed-domain.test",
            ["Access-Control-Request-Private-Network"] = "true",
            ["Access-Control-Request-Method"] = "PUT",
          }
        })
        assert.res_status(200, res)
        assert.equal("true", res.headers["Access-Control-Allow-Private-Network"])
      end)
    end)

    describe("HTTP method: others", function()
      it("gives appropriate defaults", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "cors1.test"
          }
        })
        assert.res_status(200, res)
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
        assert.is_nil(res.headers["Vary"])
      end)

      it("proxies a non-preflight OPTIONS request", function()
        local res = assert(proxy_client:send {
          method  = "OPTIONS",
          path = "/anything",
          headers = {
            ["Host"] = "cors1.test"
          }
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("OPTIONS", json.vars.request_method)
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
        assert.is_nil(res.headers["Vary"])
      end)

      it("accepts config options", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "cors2.test"
          }
        })
        assert.res_status(200, res)
        assert.equal("example.test", res.headers["Access-Control-Allow-Origin"])
        assert.equal("x-auth-token", res.headers["Access-Control-Expose-Headers"])
        assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("Origin", res.headers["Vary"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("works even when upstream timeouts", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "cors-timeout.test"
          }
        })
        assert.res_status(502, res)
        assert.equal("example.test", res.headers["Access-Control-Allow-Origin"])
        assert.equal("x-auth-token", res.headers["Access-Control-Expose-Headers"])
        assert.equal("Origin", res.headers["Vary"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("works even when a runtime error occurs", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "cors-error.test"
          }
        })
        assert.res_status(500, res)
        assert.equal("example.test", res.headers["Access-Control-Allow-Origin"])
        assert.equal("x-auth-token", res.headers["Access-Control-Expose-Headers"])
        assert.equal("Origin", res.headers["Vary"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
      end)

      it("works with 404 responses", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/asdasdasd",
          headers = {
            ["Host"] = "cors1.test"
          }
        })
        assert.res_status(404, res)
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
        assert.is_nil(res.headers["Vary"])
      end)

      it("works with 40x responses returned by another plugin", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"] = "cors4.test"
          }
        })
        assert.res_status(401, res)
        assert.equal("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Methods"])
        assert.is_nil(res.headers["Access-Control-Allow-Headers"])
        assert.is_nil(res.headers["Access-Control-Expose-Headers"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Access-Control-Max-Age"])
        assert.is_nil(res.headers["Vary"])
      end)

      it("sets CORS orgin based on origin host", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors6.test",
            ["Origin"] = "example.test"
          }
        })
        assert.res_status(200, res)
        assert.equal("example.test", res.headers["Access-Control-Allow-Origin"])
        assert.equal("Origin", res.headers["Vary"])

        local domains = {
          ["example.test"]         = true,
          ["www.example.test"]     = true,
          ["example-foo.test"]     = true,
          ["www.example-foo.test"] = true,
          ["www.example-fo0.test"] = false,
        }

        for domain in pairs(domains) do
          local res = assert(proxy_client:send {
            method  = "GET",
            headers = {
              ["Host"]   = "cors9.test",
              ["Origin"] = domain
            }
          })
          assert.res_status(200, res)
          assert.equal(domains[domain] and domain or nil,
                       res.headers["Access-Control-Allow-Origin"])
          assert.equal("Origin", res.headers["Vary"])
        end
      end)

      it("sets Vary and don't override existing Vary header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path = "/response-headers?vary=Accept-Encoding",
          headers = {
            ["Host"]   = "cors-upstream.test",
            ["Origin"] = "example.test",
          }
        })
        assert.res_status(200, res)
        assert.same({"Accept-Encoding", "Origin"}, res.headers["Vary"])
      end)

      it("does not automatically parse the host", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors6.test",
            ["Origin"] = "http://example.test"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["Access-Control-Allow-Origin"])

        -- With a different transport too
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors6.test",
            ["Origin"] = "https://example.test"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["Access-Control-Allow-Origin"])
      end)

      it("validates scheme and port", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors11.test",
            ["Origin"] = "http://my-site.test"
          }
        })
        assert.res_status(200, res)
        assert.equals("http://my-site.test", res.headers["Access-Control-Allow-Origin"])

        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors11.test",
            ["Origin"] = "http://my-site.test:80"
          }
        })
        assert.res_status(200, res)
        assert.equals("http://my-site.test", res.headers["Access-Control-Allow-Origin"])

        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors11.test",
            ["Origin"] = "http://my-site.test:8000"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["Access-Control-Allow-Origin"])

        res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors11.test",
            ["Origin"] = "https://my-site.test"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["Access-Control-Allow-Origin"])

        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors11.test",
            ["Origin"] = "https://my-other-site.test:9000"
          }
        })
        assert.res_status(200, res)
        assert.equals("https://my-other-site.test:9000", res.headers["Access-Control-Allow-Origin"])

        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors11.test",
            ["Origin"] = "https://my-other-site.test:9001"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["Access-Control-Allow-Origin"])
      end)

      it("does not sets CORS origin if origin host is not in origin_domains list", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          headers = {
            ["Host"]   = "cors6.test",
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
            ["Host"]   = "cors5.test",
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
            ["Host"]   = "cors5.test",
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
            ["Host"]   = "cors7.test",
            ["Origin"] = "http://www.example.net"
          }
        })
        assert.res_status(200, res)
        assert.equals("*", res.headers["Access-Control-Allow-Origin"])
        assert.is_nil(res.headers["Access-Control-Allow-Credentials"])
        assert.is_nil(res.headers["Vary"])
      end)

      it("removes upstream ACAO header when no match is found", function()
        local res = proxy_client:get("/response-headers", {
          query = ngx.encode_args({
            ["Response-Header"] = "is-added",
            ["Access-Control-Allow-Origin"] = "*",
          }),
          headers = {
            ["Host"]   = "cors12.test",
            ["Origin"] = "allowed-domain.test",
          }
        })

        local body = assert.res_status(200, res)
        local json = assert(cjson.decode(body))

        assert.equal("is-added", res.headers["Response-Header"])
        assert.equal("allowed-domain.test", res.headers["Access-Control-Allow-Origin"])
        assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("Origin", res.headers["Vary"])
        assert.equal("allowed-domain.test", json.headers["origin"])

        local res = proxy_client:get("/response-headers", {
          query = ngx.encode_args({
            ["Response-Header"] = "is-added",
            ["Access-Control-Allow-Origin"] = "*",
          }),
          headers = {
            ["Host"]   = "cors12.test",
            ["Origin"] = "disallowed-domain.test",
          }
        })

        local body = assert.res_status(200, res)
        local json = assert(cjson.decode(body))

        assert.equal("is-added", res.headers["Response-Header"])
        assert.equal(nil, res.headers["Access-Control-Allow-Origin"])
        assert.equal("true", res.headers["Access-Control-Allow-Credentials"])
        assert.equal("disallowed-domain.test", json.headers["origin"])
      end)
    end)
  end)
end
