local Router = require "kong.core.router"

local function reload_router()
  package.loaded["kong.core.router"] = nil
  Router = require "kong.core.router"
end

local use_case = {
  -- host
  {
    name = "api-1",
    headers = {
      ["host"] = {"domain-1.org", "domain-2.org"},
    },
  },
  -- method
  {
    name = "api-2",
    methods = {"TRACE"},
  },
  -- uri
  {
    name = "api-3",
    uris = {"/my-api"},
  },
  -- host + uri
  {
    name = "api-4",
    uris = {"/api-4"},
    headers = {
      ["host"] = {"domain-1.org", "domain-2.org"},
    },
  },
  -- host + method
  {
    name = "api-5",
    methods = {"POST", "PUT", "PATCH"},
    headers = {
      ["host"] = {"domain-1.org", "domain-2.org"},
    },
  },
  -- uri + method
  {
    name = "api-6",
    methods = {"POST", "PUT", "PATCH"},
    uris = {"/api-6"},
  },
  -- host + uri + method
  {
    name = "api-7",
    methods = {"POST", "PUT", "PATCH"},
    uris = {"/my-api-uri"},
    headers = {
      ["host"] = {"domain-with-uri-1.org", "domain-with-uri-2.org"},
    },
  },
}

describe("Router", function()
  describe("new()", function()
    describe("[errors]", function()
      it("enforces args types", function()
        assert.error_matches(function()
          Router.new()
        end, "expected arg #1 apis to be a table", nil, true)
      end)

      pending("enforces apis fields types", function()
        local router, err = Router.new {
          { name = "api-invalid" }
        }

        assert.is_nil(router)
        assert.equal("could not categorize API", err)
      end)
    end)
  end)

  describe("select()", function()
    local router = assert(Router.new(use_case))

    it("[host]", function()
      -- host
      local api_t = router.select("GET", "/", { ["host"] = "domain-1.org" })
      assert.truthy(api_t)
      assert.same(use_case[1], api_t.api)
    end)

    it("[host] ignores port", function()
      -- host
      local api_t = router.select("GET", "/", { ["host"] = "domain-1.org:123" })
      assert.truthy(api_t)
      assert.same(use_case[1], api_t.api)
    end)

    it("[uri]", function()
      -- uri
      local api_t = router.select("GET", "/my-api", {})
      assert.truthy(api_t)
      assert.same(use_case[3], api_t.api)
    end)

    it("[method]", function()
      -- method
      local api_t = router.select("TRACE", "/", {})
      assert.truthy(api_t)
      assert.same(use_case[2], api_t.api)
    end)

    it("[host + uri]", function()
      -- host + uri
      local api_t = router.select("GET", "/api-4", { ["host"] = "domain-1.org" })
      assert.truthy(api_t)
      assert.same(use_case[4], api_t.api)
    end)

    it("[host + method]", function()
      -- host + method
      local api_t = router.select("POST", "/", { ["host"] = "domain-1.org" })
      assert.truthy(api_t)
      assert.same(use_case[5], api_t.api)
    end)

    it("[uri + method]", function()
      -- uri + method
      local api_t = router.select("PUT", "/api-6", {})
      assert.truthy(api_t)
      assert.same(use_case[6], api_t.api)
    end)

    it("[host + uri + method]", function()
      -- uri + method
      local api_t = router.select("PUT", "/my-api-uri", { ["host"] = "domain-with-uri-2.org" })
      assert.truthy(api_t)
      assert.same(use_case[7], api_t.api)
    end)

    describe("[uri] as a prefix", function()
      it("matches when given [uri] is in request URI prefix", function()
        -- uri prefix
        local api_t = router.select("GET", "/my-api/some/path", {})
        assert.truthy(api_t)
        assert.same(use_case[3], api_t.api)
      end)

      it("does not superseds another API with a longer URI prefix", function()
        local use_case = {
          {
            name = "api-1",
            uris = { "/my-api/hello" },
          },
          {
            name = "api-2",
            uris = { "/my-api" },
          }
        }

        local router = assert(Router.new(use_case))

        local api_t = router.select("GET", "/my-api/hello", {})
        assert.truthy(api_t)
        assert.same(use_case[1], api_t.api)

        api_t = router.select("GET", "/my-api/hello/world", {})
        assert.truthy(api_t)
        assert.same(use_case[1], api_t.api)

        api_t = router.select("GET", "/my-api", {})
        assert.truthy(api_t)
        assert.same(use_case[2], api_t.api)

        api_t = router.select("GET", "/my-api/world", {})
        assert.truthy(api_t)
        assert.same(use_case[2], api_t.api)
      end)
    end)

    describe("wildcard domains", function()
      local use_case = {
        {
          name = "api-1",
          headers = {
            ["host"] = { "*.api.com" },
          }
        },
        {
          name = "api-2",
          headers = {
            ["host"] = { "api.*" },
          }
        }
      }

      local router = assert(Router.new(use_case))

      it("matches leftmost wildcards", function()
        local api_t = router.select("GET", "/", { ["host"] = "foo.api.com" })
        assert.truthy(api_t)
        assert.same(use_case[1], api_t.api)
      end)

      it("matches rightmost wildcards", function()
        local api_t = router.select("GET", "/", { ["host"] = "api.org" })
        assert.truthy(api_t)
        assert.same(use_case[2], api_t.api)
      end)

      it("does not take precedence over a plain host", function()
        table.insert(use_case, 1, {
          name = "api-3",
          headers = { ["host"] = { "plain.api.com" } },
        })

        table.insert(use_case, {
          name = "api-4",
          headers = { ["host"] = { "api.com" } },
        })

        finally(function()
          table.remove(use_case, 1)
          table.remove(use_case)
          router = assert(Router.new(use_case))
        end)

        router = assert(Router.new(use_case))

        local api_t = router.select("GET", "/", { ["host"] = "api.com" })
        assert.truthy(api_t)
        assert.same(use_case[4], api_t.api)

        api_t = router.select("GET", "/", { ["host"] = "api.org" })
        assert.truthy(api_t)
        assert.same(use_case[3], api_t.api)

        api_t = router.select("GET", "/", { ["host"] = "plain.api.com" })
        assert.truthy(api_t)
        assert.same(use_case[1], api_t.api)

        api_t = router.select("GET", "/", { ["host"] = "foo.api.com" })
        assert.truthy(api_t)
        assert.same(use_case[2], api_t.api)
      end)

      it("matches [wildcard/plain + uri + method]", function()
        finally(function()
          table.remove(use_case)
          router = assert(Router.new(use_case))
        end)

        table.insert(use_case, {
          name = "api-5",
          headers = { ["host"] = { "*.domain.com", "example.com" } },
          uris = { "/path" },
          methods = { "GET", "TRACE" },
        })

        router = assert(Router.new(use_case))

        local api_t = router.select("POST", "/path", { ["host"] = "foo.domain.com" })
        assert.is_nil(api_t)

        api_t = router.select("GET", "/path", { ["host"] = "foo.domain.com" })
        assert.truthy(api_t)
        assert.same(use_case[#use_case], api_t.api)

        api_t = router.select("TRACE", "/path", { ["host"] = "example.com" })
        assert.truthy(api_t)
        assert.same(use_case[#use_case], api_t.api)

        api_t = router.select("POST", "/path", { ["host"] = "foo.domain.com" })
        assert.is_nil(api_t)
      end)
    end)

    describe("edge-cases", function()
      it("[host] and [uri] have higher priority than [method]", function()
        -- host
        local api_t = router.select("TRACE", "/", { ["host"] = "domain-2.org" })
        assert.truthy(api_t)
        assert.same(use_case[1], api_t.api)

        -- uri
        local api_t = router.select("TRACE", "/my-api", {})
        assert.truthy(api_t)
        assert.same(use_case[3], api_t.api)
      end)

      describe("root / [uri]", function()
        setup(function()
          table.insert(use_case, 1, {
            name = "api-root-uri",
            uris = {"/"},
          })
        end)

        teardown(function()
          table.remove(use_case, 1)
        end)

        it("routes with GET /", function()
          local router = assert(Router.new(use_case))
          local api_t = router.select("GET", "/", {})
          assert.truthy(api_t)
          assert.same(use_case[1], api_t.api)
        end)

        it("does not superseds another API", function()
          local router = assert(Router.new(use_case))
          local api_t = router.select("GET", "/my-api", {})
          assert.truthy(api_t)
          assert.same(use_case[4], api_t.api)

          api_t = router.select("GET", "/my-api/hello/world", {})
          assert.truthy(api_t)
          assert.same(use_case[4], api_t.api)
        end)

        it("acts as a catch-all", function()
          local router = assert(Router.new(use_case))
          local api_t = router.select("GET", "/foobar/baz", {})
          assert.truthy(api_t)
          assert.same(use_case[1], api_t.api)
        end)

        it("HTTP method does not supersede non-plain URI", function()
          local use_case = {
            {
              name = "api-1",
              methods = { "GET" },
            },
            {
              name = "api-2",
              uris = { "/httpbin" },
            }
          }

          local router = assert(Router.new(use_case))
          local api_t = router.select("GET", "/httpbin", {})
          assert.truthy(api_t)
          assert.same(use_case[2], api_t.api)

          api_t = router.select("GET", "/httpbin/status/200", {})
          assert.truthy(api_t)
          assert.same(use_case[2], api_t.api)
        end)

        it("HTTP method does not supersede wildcard domain", function()
          local use_case = {
            {
              name = "api-1",
              methods = { "GET" },
            },
            {
              name = "api-2",
              headers = {
                ["Host"] = { "domain.*" }
              }
            }
          }

          local router = assert(Router.new(use_case))
          local api_t = router.select("GET", "/", {})
          assert.truthy(api_t)
          assert.same(use_case[1], api_t.api)

          api_t = router.select("GET", "/", { ["host"] = "domain.com" })
          assert.truthy(api_t)
          assert.same(use_case[2], api_t.api)
        end)
      end)

      describe("multiple APIs of same category with conflicting values", function()
        -- reload router to reset combined cached matchers
        reload_router()

        local n = 6

        setup(function()
          -- all those APIs are of the same category:
          -- [host + uri]
          for _ = 1, n - 1 do
            table.insert(use_case, {
              name = "api [host + uri]",
              uris = { "/my-uri" },
              headers = {
                ["host"] = { "domain.org" },
              },
            })
          end

          table.insert(use_case, {
            name = "target api",
            uris = { "/my-target-uri" },
            headers = {
              ["host"] = { "domain.org" },
            },
          })
        end)

        teardown(function()
          for _ = 1, n do
            table.remove(use_case)
          end
        end)

        it("matches correct API", function()
          local router = assert(Router.new(use_case))
          local api_t = router.select("GET", "/my-target-uri", { ["host"] = "domain.org" })
          assert.truthy(api_t)
          assert.same(use_case[#use_case], api_t.api)
        end)
      end)
    end)

    describe("misses", function()
      it("invalid [host]", function()
        assert.is_nil(router.select("GET", "/", { ["host"] = "domain-3.org" }))
      end)

      it("invalid host in [host + uri]", function()
        assert.is_nil(router.select("GET", "/api-4", { ["host"] = "domain-3.org" }))
      end)

      it("invalid host in [host + method]", function()
        assert.is_nil(router.select("GET", "/", { ["host"] = "domain-3.org" }))
      end)

      it("invalid method in [host + uri + method]", function()
        assert.is_nil(router.select("GET", "/some-uri", { ["host"] = "domain-with-uri-2.org" }))
      end)

      it("invalid uri in [host + uri + method]", function()
        assert.is_nil(router.select("PUT", "/some-uri-foo", { ["host"] = "domain-with-uri-2.org" }))
      end)

      it("does not match when given [uri] is in URI but not in prefix", function()
        local api_t = router.select("GET", "/some-other-prefix/my-api", {})
        assert.is_nil(api_t)
      end)
    end)

    describe("#benchmarks", function()
      --[[
        Run:
            $ busted --tags=benchmarks <router_spec.lua>

        To estimate how much time matching an API in a worst-case scenario
        with a set of ~1000 registered APIs would take.

        We are aiming at sub-ms latency.
      ]]

      describe("plain [host]", function()
        local router
        local target_domain
        local benchmark_use_cases = {}

        setup(function()
          for i = 1, 10^5 do
            benchmark_use_cases[i] = {
              name = "api-" .. i,
              headers = {
                ["host"] = { "domain-" .. i .. ".org" },
              },
            }
          end

          target_domain = "domain-" .. #benchmark_use_cases .. ".org"
          router = assert(Router.new(benchmark_use_cases))
        end)

        it("takes < 1ms", function()
          local api_t = router.select("GET", "/", { ["host"] = target_domain })
          assert.truthy(api_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases], api_t.api)
        end)
      end)

      describe("[method + uri + host]", function()
        local router
        local target_uri
        local target_domain
        local benchmark_use_cases = {}

        setup(function()
          local n = 10^5

          for i = 1, n - 1 do
            -- insert a lot of APIs that don't match (missing methods)
            -- but have conflicting uris and hosts (domain-<n>.org)

            benchmark_use_cases[i] = {
              name = "api-" .. i,
              --methods = { "POST" },
              uris = { "/my-api-" .. n },
              headers = {
                ["host"] = { "domain-" .. n .. ".org" },
              },
            }
          end

          -- insert our target API, which has the proper method as well
          benchmark_use_cases[n] = {
            name = "api-" .. n,
            methods = { "POST" },
            uris = { "/my-api-" .. n },
            headers = {
              ["host"] = { "domain-" .. n .. ".org" },
            },
          }

          target_uri = "/my-api-" .. n
          target_domain = "domain-" .. n .. ".org"
          router = assert(Router.new(benchmark_use_cases))
        end)

        it("takes < 1ms", function()
          local api_t = router.select("POST", target_uri, { ["host"] = target_domain })
          assert.truthy(api_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases], api_t.api)
        end)
      end)

      describe("multiple APIs of same category with identical values", function()
        local router
        local target_uri
        local target_domain
        local benchmark_use_cases = {}

        setup(function()
          local n = 10^5

          for i = 1, n - 1 do
            -- all our APIs here use domain.org as the domain
            -- they all are [host + uri] category
            benchmark_use_cases[i] = {
              name = "api-" .. i,
              uris = { "/my-api-" .. n },
              headers = {
                ["host"] = { "domain.org" },
              },
            }
          end

          -- this one too, but our target will be a
          -- different URI
          benchmark_use_cases[n] = {
            name = "api-" .. n,
            uris = { "/my-real-api" },
            headers = {
              ["host"] = { "domain.org" },
            },
          }

          target_uri = "/my-real-api"
          target_domain = "domain.org"
          router = assert(Router.new(benchmark_use_cases))
        end)

        it("takes < 1ms", function()
          local api_t = router.select("GET", target_uri, { ["host"] = target_domain })
          assert.truthy(api_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases], api_t.api)
        end)
      end)
    end)

    describe("[errors]", function()
      it("enforces args types", function()
        assert.error_matches(function()
          router.select()
        end, "arg #1 method must be a string", nil, true)

        assert.error_matches(function()
          router.select("GET")
        end, "arg #2 uri must be a string", nil, true)

        assert.error_matches(function()
          router.select("GET", "/")
        end, "arg #3 headers must be a table", nil, true)
      end)
    end)
  end)

  describe("exec()", function()
    local function mock_ngx(method, uri, headers)
      local _ngx
      _ngx = {
        re = ngx.re,
        var = {
          uri = uri
        },
        req = {
          set_uri = function(uri)
            _ngx.var.uri = uri
          end,
          get_method = function()
            return method
          end,
          get_headers = function()
            return headers
          end
        }
      }

      return _ngx
    end

    it("returns api/scheme/host/port", function()
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api" },
          upstream_url = "http://httpbin.org",
        },
        {
          name = "api-2",
          uris = { "/my-api-2" },
          upstream_url = "https://httpbin.org",
        }
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/my-api", {})
      local api, upstream = router.exec(_ngx)
      assert.same(use_case_apis[1], api)
      assert.equal("http", upstream.scheme)
      assert.equal("httpbin.org", upstream.host)
      assert.equal(80, upstream.port)

      local _ngx = mock_ngx("GET", "/my-api-2", {})
      api, upstream = router.exec(_ngx)
      assert.same(use_case_apis[2], api)
      assert.equal("https", upstream.scheme)
      assert.equal("httpbin.org", upstream.host)
      assert.equal(443, upstream.port)
    end)

    it("parses path component from upstream_url property", function()
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api" },
          upstream_url = "http://httpbin.org/get",
        }
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/my-api", {})
      local api, upstream = router.exec(_ngx)
      assert.same(use_case_apis[1], api)
      assert.equal("/get", upstream.path)
    end)

    it("parses upstream_url port", function()
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api" },
          upstream_url = "http://httpbin.org:8080",
        },
        {
          name = "api-2",
          uris = { "/my-api-2" },
          upstream_url = "https://httpbin.org:8443",
        }
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/my-api", {})
      local _, upstream = router.exec(_ngx)
      assert.equal(8080, upstream.port)

      local _ngx = mock_ngx("GET", "/my-api-2", {})
      _, upstream = router.exec(_ngx)
      assert.equal(8443, upstream.port)
    end)

    describe("grab_headers", function()
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api" },
        }
      }

      it("does not read request headers if not required", function()
        local _ngx = mock_ngx("GET", "/my-api", {})
        spy.on(_ngx.req, "get_headers")

        local router = assert(Router.new(use_case_apis))

        local api = router.exec(_ngx)
        assert.same(use_case_apis[1], api)
        assert.spy(_ngx.req.get_headers).was.not_called()
      end)

      it("reads request headers if required", function()
        table.insert(use_case_apis, {
          name = "api-2",
          uris = { "/my-api" },
          headers = {
            host = { "my-api.com" },
          }
        })

        local _ngx = mock_ngx("GET", "/my-api", { host = "my-api.com" })
        spy.on(_ngx.req, "get_headers")

        local router = assert(Router.new(use_case_apis))

        local api = router.exec(_ngx)
        assert.same(use_case_apis[2], api)
        assert.spy(_ngx.req.get_headers).was.called(1)
      end)
    end)

    describe("stripped uris", function()
      local router
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api", "/this-api" },
          strip_uri = true
        },
        -- don't strip this API's matching URI
        {
          name = "api-2",
          methods = { "POST" },
          uris = { "/my-api", "/this-api" },
        },
      }

      setup(function()
        router = assert(Router.new(use_case_apis))
      end)

      it("strips the specified uris from the given uri if matching", function()
        local _ngx = mock_ngx("GET", "/my-api/hello/world", {})

        local api = router.exec(_ngx)
        assert.same(use_case_apis[1], api)
        assert.equal("/hello/world", _ngx.var.uri)
      end)

      it("strips if matched URI is plain (not a prefix)", function()
        local _ngx = mock_ngx("GET", "/my-api", {})

        local api = router.exec(_ngx)
        assert.same(use_case_apis[1], api)
        assert.equal("/", _ngx.var.uri)
      end)

      it("doesn't strip if 'strip_uri' is not enabled", function()
        local _ngx = mock_ngx("POST", "/my-api/hello/world", {})

        local api = router.exec(_ngx)
        assert.same(use_case_apis[2], api)
        assert.equal("/my-api/hello/world", _ngx.var.uri)
      end)

      it("does not strips root / URI", function()
        local use_case_apis = {
          {
            name = "root-uri",
            uris = { "/" },
            strip_uri = true,
          }
        }

        local router = assert(Router.new(use_case_apis))

        local _ngx = mock_ngx("POST", "/my-api/hello/world", {})

        local api = router.exec(_ngx)
        assert.same(use_case_apis[1], api)
        assert.equal("/my-api/hello/world", _ngx.var.uri)
      end)

      it("can find an API with stripped URI several times in a row", function()
        local _ngx = mock_ngx("GET", "/my-api", {})

        local api = router.exec(_ngx)
        assert.same(use_case_apis[1], api)
        assert.equal("/", _ngx.var.uri)

        _ngx = mock_ngx("GET", "/my-api", {})
        local api2 = router.exec(_ngx)
        assert.same(use_case_apis[1], api2)
        assert.equal("/", _ngx.var.uri)
      end)

      it("can proxy an API with stripped URI with different URIs in a row", function()
        local _ngx = mock_ngx("GET", "/my-api", {})

        local api = router.exec(_ngx)
        assert.same(use_case_apis[1], api)
        assert.equal("/", _ngx.var.uri)

        _ngx = mock_ngx("GET", "/this-api", {})
        local api2 = router.exec(_ngx)
        assert.same(use_case_apis[1], api2)
        assert.equal("/", _ngx.var.uri)
      end)
    end)

    describe("preserve Host header", function()
      local router
      local use_case_apis = {
        -- use the request's Host header
        {
          name = "api-1",
          upstream_url = "http://httpbin.org",
          preserve_host = true,
          headers = {
            ["host"] = { "preserve.com" },
          }
        },
        -- use the API's upstream_url's Host
        {
          name = "api-2",
          upstream_url = "http://httpbin.org",
          preserve_host = false,
          headers = {
            ["host"] = { "discard.com" },
          }
        },
      }

      setup(function()
        router = assert(Router.new(use_case_apis))
      end)

      describe("when preserve_host is true", function()
        local host = "preserve.com"

        it("uses the request's Host header", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host })

          local api, _, host_header = router.exec(_ngx)
          assert.same(use_case_apis[1], api)
          assert.equal(host, host_header)
        end)

        it("uses the request's Host header incl. port", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host .. ":123" })

          local api, _, host_header = router.exec(_ngx)
          assert.same(use_case_apis[1], api)
          assert.equal(host .. ":123", host_header)
        end)

        it("does not change the target upstream", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host })

          local api, upstream = router.exec(_ngx)
          assert.same(use_case_apis[1], api)
          assert.equal("httpbin.org", upstream.host)
        end)
      end)

      describe("when preserve_host is false", function()
        local host = "discard.com"

        it("does not change the target upstream", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host })

          local api, upstream = router.exec(_ngx)
          assert.same(use_case_apis[2], api)
          assert.equal("httpbin.org", upstream.host)
        end)

        it("does not set the host_header", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host })

          local api, _, host_header = router.exec(_ngx)
          assert.same(use_case_apis[2], api)
          assert.is_nil(host_header)
        end)
      end)
    end)
  end)
end)
