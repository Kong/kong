local Router = require "kong.api_router"

local function reload_router()
  package.loaded["kong.api_router"] = nil
  Router = require "kong.api_router"
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

      it("enforces apis fields types", function()
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
      local match_t = router.select("GET", "/", "domain-1.org")
      assert.truthy(match_t)
      assert.same(use_case[1], match_t.api)
    end)

    it("[host] ignores port", function()
      -- host
      local match_t = router.select("GET", "/", "domain-1.org:123")
      assert.truthy(match_t)
      assert.same(use_case[1], match_t.api)
    end)

    it("[uri]", function()
      -- uri
      local match_t = router.select("GET", "/my-api", "domain.org")
      assert.truthy(match_t)
      assert.same(use_case[3], match_t.api)
    end)

    it("[method]", function()
      -- method
      local match_t = router.select("TRACE", "/", "domain.org")
      assert.truthy(match_t)
      assert.same(use_case[2], match_t.api)
    end)

    it("[host + uri]", function()
      -- host + uri
      local match_t = router.select("GET", "/api-4", "domain-1.org")
      assert.truthy(match_t)
      assert.same(use_case[4], match_t.api)
    end)

    it("[host + method]", function()
      -- host + method
      local match_t = router.select("POST", "/", "domain-1.org")
      assert.truthy(match_t)
      assert.same(use_case[5], match_t.api)
    end)

    it("[uri + method]", function()
      -- uri + method
      local match_t = router.select("PUT", "/api-6", "domain.org")
      assert.truthy(match_t)
      assert.same(use_case[6], match_t.api)
    end)

    it("[host + uri + method]", function()
      -- uri + method
      local match_t = router.select("PUT", "/my-api-uri",
                                    "domain-with-uri-2.org")
      assert.truthy(match_t)
      assert.same(use_case[7], match_t.api)
    end)

    describe("[uri prefix]", function()
      it("matches when given [uri] is in request URI prefix", function()
        -- uri prefix
        local match_t = router.select("GET", "/my-api/some/path", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[3], match_t.api)
      end)

      it("does not supersede another API with a longer [uri]", function()
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

        local match_t = router.select("GET", "/my-api/hello", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("GET", "/my-api/hello/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("GET", "/my-api", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)

        match_t = router.select("GET", "/my-api/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)

      it("does not superseds another API with a longer [uri] while [methods] are also defined", function()
        local use_case = {
          {
            name = "api-1",
            methods = { "POST", "PUT", "GET" },
            uris = { "/my-api" },
          },
          {
            name = "api-2",
            methods = { "POST", "PUT", "GET" },
            uris = { "/my-api/hello" },
          }
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/my-api/hello", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)

        match_t = router.select("GET", "/my-api/hello/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)

        match_t = router.select("GET", "/my-api", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("GET", "/my-api/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)
      end)

      it("does not superseds another API with a longer [uri] while [hosts] are also defined", function()
        local use_case = {
          {
            name = "api-1",
            uris = { "/my-api" },
            headers = {
              ["host"] = { "domain.org" },
            },
          },
          {
            name = "api-2",
            uris = { "/my-api/hello" },
            headers = {
              ["host"] = { "domain.org" },
            },
          }
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/my-api/hello", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)

        match_t = router.select("GET", "/my-api/hello/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)

        match_t = router.select("GET", "/my-api", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("GET", "/my-api/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)
      end)

      it("only matches [uri prefix] as a prefix (anchored mode)", function()
        local use_case = {
          {
            name = "api-1",
            uris = { "/something/my-api" },
          },
          {
            name = "api-2",
            uris = { "/my-api" },
            headers = {
              ["host"] = { "example.com" },
            },
          }
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/something/my-api", "example.com")
        assert.truthy(match_t)
        -- would be api-2 if URI matching was not prefix-only (anchored mode)
        assert.same(use_case[1], match_t.api)
      end)
    end)

    describe("[uri regex]", function()
      it("matches with [uri regex]", function()
        local use_case = {
          {
            name = "api-1",
            uris = { [[/users/\d+/profile]] },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/users/123/profile", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)
      end)

      it("matches the right API when several ones have a [uri regex]", function()
        local use_case = {
          {
            name = "api-1",
            uris = { [[/api/persons/\d{3}]] },
          },
          {
            name = "api-2",
            uris = { [[/api/persons/\d{3}/following]] },
          },
          {
            name = "api-3",
            uris = { [[/api/persons/\d{3}/[a-z]+]] },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/api/persons/456", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)
      end)

      it("matches a [uri regex] even if a [prefix uri] got a match", function()
        local use_case = {
          {
            name = "api-1",
            uris = { [[/api/persons]] },
          },
          {
            name = "api-2",
            uris = { [[/api/persons/\d+/profile]] },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/api/persons/123/profile",
                                      "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)
    end)

    describe("[wildcard host]", function()
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
        local match_t = router.select("GET", "/", "foo.api.com", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)
      end)

      it("matches rightmost wildcards", function()
        local match_t = router.select("GET", "/", "api.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
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

        local match_t = router.select("GET", "/", "api.com")
        assert.truthy(match_t)
        assert.same(use_case[4], match_t.api)

        match_t = router.select("GET", "/", "api.org")
        assert.truthy(match_t)
        assert.same(use_case[3], match_t.api)

        match_t = router.select("GET", "/", "plain.api.com")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("GET", "/", "foo.api.com")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
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

        local match_t = router.select("POST", "/path", "foo.domain.com")
        assert.is_nil(match_t)

        match_t = router.select("GET", "/path", "foo.domain.com")
        assert.truthy(match_t)
        assert.same(use_case[#use_case], match_t.api)

        match_t = router.select("TRACE", "/path", "example.com")
        assert.truthy(match_t)
        assert.same(use_case[#use_case], match_t.api)

        match_t = router.select("POST", "/path", "foo.domain.com")
        assert.is_nil(match_t)
      end)
    end)

    describe("[wildcard host] + [uri regex]", function()
      it("matches", function()
        local use_case = {
          {
            name       = "api-1",
            uris       = { [[/users/\d+/profile]] },
            headers    = {
              ["host"] = { "*.example.com" },
            },
          },
          {
            name       = "api-2",
            uris       = { [[/users]] },
            headers    = {
              ["host"] = { "*.example.com" },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/users/123/profile",
                                      "test.example.com")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("GET", "/users", "test.example.com")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)
    end)

    describe("edge-cases", function()
      it("[host] and [uri] have higher priority than [method]", function()
        -- host
        local match_t = router.select("TRACE", "/", "domain-2.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        -- uri
        local match_t = router.select("TRACE", "/my-api", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[3], match_t.api)
      end)

      it("half [uri] and [host] match does not supersede another API", function()
        local use_case = {
          {
            name       = "api-1",
            uris       = { "/v1/path"  },
            headers    = {
              ["host"] = { "host1.com" },
            }
          },
          {
            name       = "api-2",
            uris       = { "/" },
            headers    = {
              ["host"] = { "host2.com" },
            }
          }
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/v1/path", "host1.com")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("GET", "/v1/path", "host2.com")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)

      it("half [wildcard host] and [method] match does not supersede another API", function()
        local use_case = {
          {
            name       = "api-1",
            methods    = { "GET" },
            headers    = {
              ["host"] = { "host.*" },
            }
          },
          {
            name       = "api-2",
            methods    = { "POST" },
            headers    = {
              ["host"] = { "host.*" },
            }
          }
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/", "host.com")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("POST", "/", "host.com")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)

      it("half [uri regex] and [method] match does not supersede another API", function()
        local use_case = {
          {
            name = "api-1",
            methods = { "GET" },
            uris = { [[/users/\d+/profile]] },
          },
          {
            name = "api-2",
            methods = { "POST" },
            uris = { [[/users/\d*/profile]] },
          }
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/users/123/profile", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("POST", "/users/123/profile", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)

      it("[method] does not supersede [uri prefix]", function()
        local use_case = {
          {
            name = "api-1",
            methods = { "GET" },
          },
          {
            name = "api-2",
            uris = { "/example" },
          }
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/example", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)

        match_t = router.select("GET", "/example/status/200", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)

      it("[method] does not supersede [wildcard host]", function()
        local use_case = {
          {
            name    = "api-1",
            methods = { "GET" },
          },
          {
            name       = "api-2",
            headers    = {
              ["Host"] = { "domain.*" }
            }
          }
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/", "nothing.com")
        assert.truthy(match_t)
        assert.same(use_case[1], match_t.api)

        match_t = router.select("GET", "/", "domain.com")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)

      it("does not supersede another API with a longer [uri prefix]", function()
        local use_case = {
          {
            name = "api-1",
            uris = { "/a", "/bbbbbbb" }
          },
          {
            name = "api-2",
            uris = { "/a/bb" }
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/a/bb/foobar", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2], match_t.api)
      end)

      describe("root / [uri]", function()
        lazy_setup(function()
          table.insert(use_case, 1, {
            name = "api-root-uri",
            uris = {"/"},
          })
        end)

        lazy_teardown(function()
          table.remove(use_case, 1)
        end)

        it("request with [method]", function()
          local router = assert(Router.new(use_case))
          local match_t = router.select("GET", "/", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1], match_t.api)
        end)

        it("does not supersede another API", function()
          local router = assert(Router.new(use_case))
          local match_t = router.select("GET", "/my-api", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[4], match_t.api)

          match_t = router.select("GET", "/my-api/hello/world", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[4], match_t.api)
        end)

        it("acts as a catch-all API", function()
          local router = assert(Router.new(use_case))
          local match_t = router.select("GET", "/foobar/baz", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1], match_t.api)
        end)
      end)

      describe("multiple APIs of same category with conflicting values", function()
        -- reload router to reset combined cached matchers
        reload_router()

        local n = 6

        lazy_setup(function()
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

        lazy_teardown(function()
          for _ = 1, n do
            table.remove(use_case)
          end
        end)

        it("matches correct API", function()
          local router = assert(Router.new(use_case))
          local match_t = router.select("GET", "/my-target-uri", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[#use_case], match_t.api)
        end)
      end)

      it("does not incorrectly match another API which has a longer [uri]", function()
        local use_case = {
          {
            name = "api-1",
            uris = { "/a", "/bbbbbbb" }
          },
          {
            name = "api-2",
            uris = { "/a/bb" }
          },
        }

        local router = assert(Router.new(use_case))

        local api_t = router.select("GET", "/a/bb/foobar", "domain.org")
        assert.truthy(api_t)
        assert.same(use_case[2], api_t.api)
      end)
    end)

    describe("misses", function()
      it("invalid [host]", function()
        assert.is_nil(router.select("GET", "/", "domain-3.org"))
      end)

      it("invalid host in [host + uri]", function()
        assert.is_nil(router.select("GET", "/api-4", "domain-3.org"))
      end)

      it("invalid host in [host + method]", function()
        assert.is_nil(router.select("GET", "/", "domain-3.org"))
      end)

      it("invalid method in [host + uri + method]", function()
        assert.is_nil(router.select("GET", "/some-uri", "domain-with-uri-2.org"))
      end)

      it("invalid uri in [host + uri + method]", function()
        assert.is_nil(router.select("PUT", "/some-uri-foo",
                                    "domain-with-uri-2.org"))
      end)

      it("does not match when given [uri] is in URI but not in prefix", function()
        local match_t = router.select("GET", "/some-other-prefix/my-api",
                                      "domain.org")
        assert.is_nil(match_t)
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

        lazy_setup(function()
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
          local match_t = router.select("GET", "/", target_domain)
          assert.truthy(match_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases], match_t.api)
        end)
      end)

      describe("[method + uri + host]", function()
        local router
        local target_uri
        local target_domain
        local benchmark_use_cases = {}

        lazy_setup(function()
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
          local match_t = router.select("POST", target_uri, target_domain)
          assert.truthy(match_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases], match_t.api)
        end)
      end)

      describe("multiple APIs of same category with identical values", function()
        local router
        local target_uri
        local target_domain
        local benchmark_use_cases = {}

        lazy_setup(function()
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
          local match_t = router.select("GET", target_uri, target_domain)
          assert.truthy(match_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases], match_t.api)
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
        end, "arg #3 host must be a string", nil, true)
      end)
    end)
  end)

  describe("exec()", function()
    local spy_stub = {
      nop = function() end
    }

    local function mock_ngx(method, request_uri, headers)
      local _ngx
      _ngx = {
        re = ngx.re,
        var = setmetatable({
          request_uri = request_uri,
          http_kong_debug = headers.kong_debug
        }, {
          __index = function(_, key)
            if key == "http_host" then
              spy_stub.nop()
              return headers.host
            end
          end
        }),
        req = {
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

    it("[uri + empty host]", function()
      -- uri only (no Host)
      -- Supported for HTTP/1.0 requests without a Host header
      -- Regression for https://github.com/Kong/kong/issues/3435
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api" },
          upstream_url = "http://example.org",
        },
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/my-api", { ["host"] = nil })
      local match_t = router.exec(_ngx)
      assert.same(use_case_apis[1], match_t.api)
    end)

    it("returns parsed upstream_url + upstream_uri", function()
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api" },
          upstream_url = "http://example.org",
        },
        {
          name = "api-2",
          uris = { "/my-api-2" },
          upstream_url = "https://example.org",
        }
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/my-api", { ["host"] = "domain.org" })
      local match_t = router.exec(_ngx)
      assert.same(use_case_apis[1], match_t.api)

      -- upstream_url_t
      assert.equal("http", match_t.upstream_url_t.scheme)
      assert.equal("example.org", match_t.upstream_url_t.host)
      assert.equal(80, match_t.upstream_url_t.port)

      -- upstream_uri
      assert.is_nil(match_t.upstream_host) -- only when `preserve_host = true`
      assert.equal("/my-api", match_t.upstream_uri)

      _ngx = mock_ngx("GET", "/my-api-2", { ["host"] = "domain.org" })
      match_t = router.exec(_ngx)
      assert.same(use_case_apis[2], match_t.api)

      -- upstream_url_t
      assert.equal("https", match_t.upstream_url_t.scheme)
      assert.equal("example.org", match_t.upstream_url_t.host)
      assert.equal(443, match_t.upstream_url_t.port)

      -- upstream_uri
      assert.is_nil(match_t.upstream_host) -- only when `preserve_host = true`
      assert.equal("/my-api-2", match_t.upstream_uri)
    end)

    it("returns matched_host + matched_uri + matched_method", function()
      local use_case_apis = {
        {
          name       = "api-1",
          methods    = { "GET" },
          uris       = { "/my-api" },
          headers    = {
            ["host"] = { "host.com" },
          },
        },
        {
          name       = "api-2",
          uris       = { "/my-api" },
          headers    = {
            ["host"] = { "host.com" },
          },
        },
        {
          name       = "api-3",
          headers    = {
            ["host"] = { "*.host.com" },
          },
        },
        {
          name = "api-4",
          uris = { [[/users/\d+/profile]] },
        },
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/my-api", { ["host"] = "host.com" })
      local match_t = router.exec(_ngx)
      assert.same(use_case_apis[1], match_t.api)
      assert.equal("host.com", match_t.matches.host)
      assert.equal("/my-api", match_t.matches.uri)
      assert.equal("GET", match_t.matches.method)

      _ngx = mock_ngx("GET", "/my-api/prefix/match", { ["host"] = "host.com" })
      match_t = router.exec(_ngx)
      assert.same(use_case_apis[1], match_t.api)
      assert.equal("host.com", match_t.matches.host)
      assert.equal("/my-api", match_t.matches.uri)
      assert.equal("GET", match_t.matches.method)

      _ngx = mock_ngx("POST", "/my-api", { ["host"] = "host.com" })
      match_t = router.exec(_ngx)
      assert.same(use_case_apis[2], match_t.api)
      assert.equal("host.com", match_t.matches.host)
      assert.equal("/my-api", match_t.matches.uri)
      assert.is_nil(match_t.matches.method)

      _ngx = mock_ngx("GET", "/", { ["host"] = "test.host.com" })
      match_t = router.exec(_ngx)
      assert.same(use_case_apis[3], match_t.api)
      assert.equal("*.host.com", match_t.matches.host)
      assert.is_nil(match_t.matches.uri)
      assert.is_nil(match_t.matches.method)

      _ngx = mock_ngx("GET", "/users/123/profile", { ["host"] = "domain.org" })
      match_t = router.exec(_ngx)
      assert.same(use_case_apis[4], match_t.api)
      assert.is_nil(match_t.matches.host)
      assert.equal([[/users/\d+/profile]], match_t.matches.uri)
      assert.is_nil(match_t.matches.method)
    end)

    it("returns uri_captures from a [uri regex]", function()
      local use_case = {
        {
          name = "api-1",
          uris = { [[/users/(?P<user_id>\d+)/profile/?(?P<scope>[a-z]*)]] },
        },
      }

      local router = assert(Router.new(use_case))

      local _ngx = mock_ngx("GET", "/users/1984/profile",
                            { ["host"] = "domain.org" })
      local match_t = router.exec(_ngx)
      assert.equal("1984", match_t.matches.uri_captures[1])
      assert.equal("1984", match_t.matches.uri_captures.user_id)
      assert.equal("",     match_t.matches.uri_captures[2])
      assert.equal("",     match_t.matches.uri_captures.scope)
      -- returns the full match as well
      assert.equal("/users/1984/profile", match_t.matches.uri_captures[0])
      -- no stripped_uri capture
      assert.is_nil(match_t.matches.uri_captures.stripped_uri)
      assert.equal(2, #match_t.matches.uri_captures)

      -- again, this time from the LRU cache
      match_t = router.exec(_ngx)
      assert.equal("1984", match_t.matches.uri_captures[1])
      assert.equal("1984", match_t.matches.uri_captures.user_id)
      assert.equal("",     match_t.matches.uri_captures[2])
      assert.equal("",     match_t.matches.uri_captures.scope)
      -- returns the full match as well
      assert.equal("/users/1984/profile", match_t.matches.uri_captures[0])
      -- no stripped_uri capture
      assert.is_nil(match_t.matches.uri_captures.stripped_uri)
      assert.equal(2, #match_t.matches.uri_captures)

      _ngx = mock_ngx("GET", "/users/1984/profile/email",
                      { ["host"] = "domain.org" })
      match_t = router.exec(_ngx)
      assert.equal("1984",  match_t.matches.uri_captures[1])
      assert.equal("1984",  match_t.matches.uri_captures.user_id)
      assert.equal("email", match_t.matches.uri_captures[2])
      assert.equal("email", match_t.matches.uri_captures.scope)
      -- returns the full match as well
      assert.equal("/users/1984/profile/email", match_t.matches.uri_captures[0])
      -- no stripped_uri capture
      assert.is_nil(match_t.matches.uri_captures.stripped_uri)
      assert.equal(2, #match_t.matches.uri_captures)
    end)

    it("returns no uri_captures from a [uri prefix] match", function()
      local use_case = {
        {
          name      = "api-1",
          uris      = { "/hello" },
          strip_uri = true,
        },
      }

      local router = assert(Router.new(use_case))

      local _ngx = mock_ngx("GET", "/hello/world", { ["host"] = "domain.org" })
      local match_t = router.exec(_ngx)
      assert.equal("/world", match_t.upstream_uri)
      assert.is_nil(match_t.matches.uri_captures)
    end)

    it("returns no uri_captures from a [uri regex] match without groups", function()
      local use_case = {
        {
          name = "api-1",
          uris = { [[/users/\d+/profile]] },
        },
      }

      local router = assert(Router.new(use_case))

      local _ngx = mock_ngx("GET", "/users/1984/profile",
                            { ["host"] = "domain.org" })
      local match_t = router.exec(_ngx)
      assert.is_nil(match_t.matches.uri_captures)
    end)

    it("parses path component from upstream_url property", function()
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api" },
          upstream_url = "http://example.org/get",
        }
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/my-api", { ["host"] = "domain.org" })
      local match_t = router.exec(_ngx)
      assert.same(use_case_apis[1], match_t.api)
      assert.equal("/get", match_t.upstream_url_t.path)
    end)

    it("parses upstream_url port", function()
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api" },
          upstream_url = "http://example.org:8080",
        },
        {
          name = "api-2",
          uris = { "/my-api-2" },
          upstream_url = "https://example.org:8443",
        }
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/my-api", { ["host"] = "domain.org" })
      local match_t = router.exec(_ngx)
      assert.equal(8080, match_t.upstream_url_t.port)

      _ngx = mock_ngx("GET", "/my-api-2", { ["host"] = "domain.org" })
      match_t = router.exec(_ngx)
      assert.equal(8443, match_t.upstream_url_t.port)
    end)

    it("allows url encoded uris", function()
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/endel%C3%B8st" },
        },
      }

      local router = assert(Router.new(use_case_apis))

      local _ngx = mock_ngx("GET", "/endel%C3%B8st", { ["host"] = "domain.org" })
      local match_t = router.exec(_ngx)
      assert.same(use_case_apis[1], match_t.api)
      assert.equal("/endel%C3%B8st", match_t.upstream_uri)
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

      lazy_setup(function()
        router = assert(Router.new(use_case_apis))
      end)

      it("strips the specified uris from the given uri if matching", function()
        local _ngx = mock_ngx("GET", "/my-api/hello/world",
                              { ["host"] = "domain.org" })

        local match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/hello/world", match_t.upstream_uri)
      end)

      it("strips if matched URI is plain (not a prefix)", function()
        local _ngx = mock_ngx("GET", "/my-api", { ["host"] = "domain.org" })

        local match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/", match_t.upstream_uri)
      end)

      it("doesn't strip if 'strip_uri' is not enabled", function()
        local _ngx = mock_ngx("POST", "/my-api/hello/world",
                              { ["host"] = "domain.org" })

        local match_t = router.exec(_ngx)
        assert.same(use_case_apis[2], match_t.api)
        assert.equal("/my-api/hello/world", match_t.upstream_uri)
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

        local _ngx = mock_ngx("POST", "/my-api/hello/world",
                              { ["host"] = "domain.org" })

        local match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/my-api/hello/world", match_t.upstream_uri)
      end)

      it("can find an API with stripped URI several times in a row", function()
        local _ngx = mock_ngx("GET", "/my-api", { ["host"] = "domain.org" })
        local match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/my-api", { ["host"] = "domain.org" })
        match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/", match_t.upstream_uri)
      end)

      it("can proxy an API with stripped URI with different URIs in a row", function()
        local _ngx = mock_ngx("GET", "/my-api", { ["host"] = "domain.org" })

        local match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/this-api", { ["host"] = "domain.org" })
        match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/my-api", { ["host"] = "domain.org" })
        match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/this-api", { ["host"] = "domain.org" })
        match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/", match_t.upstream_uri)
      end)

      it("strips url encoded uris", function()
        local use_case_apis = {
          {
            name      = "api-1",
            uris      = { "/endel%C3%B8st" },
            strip_uri = true,
          },
        }

        local router = assert(Router.new(use_case_apis))

        local _ngx = mock_ngx("GET", "/endel%C3%B8st", { ["host"] = "domain.org" })
        local match_t = router.exec(_ngx)
        assert.same(use_case_apis[1], match_t.api)
        assert.equal("/", match_t.upstream_uri)
      end)

      it("strips a [uri regex]", function()
        local use_case = {
          {
            name      = "api-1",
            strip_uri = true,
            uris      = { [[/users/\d+/profile]] },
          },
        }

        local router = assert(Router.new(use_case))

        local _ngx = mock_ngx("GET", "/users/123/profile/hello/world",
                              { ["host"] = "domain.org" })
        local match_t = router.exec(_ngx)
        assert.equal("/hello/world", match_t.upstream_uri)
      end)

      it("strips a [uri regex] with a capture group", function()
        local use_case = {
          {
            name      = "api-1",
            strip_uri = true,
            uris      = { [[/users/(\d+)/profile]] },
          },
        }

        local router = assert(Router.new(use_case))

        local _ngx = mock_ngx("GET", "/users/123/profile/hello/world",
                              { ["host"] = "domain.org" })
        local match_t = router.exec(_ngx)
        assert.equal("/hello/world", match_t.upstream_uri)
      end)
    end)

    describe("preserve Host header", function()
      local router
      local use_case_apis = {
        -- use the request's Host header
        {
          name = "api-1",
          upstream_url = "http://example.org",
          preserve_host = true,
          headers = {
            ["host"] = { "preserve.com" },
          }
        },
        -- use the API's upstream_url's Host
        {
          name = "api-2",
          upstream_url = "http://example.org",
          preserve_host = false,
          headers = {
            ["host"] = { "discard.com" },
          }
        },
      }

      lazy_setup(function()
        router = assert(Router.new(use_case_apis))
      end)

      describe("when preserve_host is true", function()
        local host = "preserve.com"

        it("uses the request's Host header", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host })

          local match_t = router.exec(_ngx)
          assert.same(use_case_apis[1], match_t.api)
          assert.equal(host, match_t.upstream_host)
        end)

        it("uses the request's Host header incl. port", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host .. ":123" })

          local match_t = router.exec(_ngx)
          assert.same(use_case_apis[1], match_t.api)
          assert.equal(host .. ":123", match_t.upstream_host)
        end)

        it("does not change the target upstream", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host })

          local match_t = router.exec(_ngx)
          assert.same(use_case_apis[1], match_t.api)
          assert.equal("example.org", match_t.upstream_url_t.host)
        end)

        it("uses the request's Host header when `grab_header` is disabled", function()
          local use_case_apis = {
            {
              name          = "api-1",
              upstream_url  = "http://example.org",
              preserve_host = true,
              uris          = { "/foo" },
            }
          }

          local router = assert(Router.new(use_case_apis))

          local _ngx = mock_ngx("GET", "/foo", { ["host"] = "preserve.com" })

          local match_t = router.exec(_ngx)
          assert.same(use_case_apis[1], match_t.api)
          assert.equal("preserve.com", match_t.upstream_host)
        end)

        it("uses the request's Host header if an API with no host was cached", function()
          -- This is a regression test for:
          -- https://github.com/Kong/kong/issues/2825
          -- Ensure cached APIs (in the LRU cache) still get proxied with the
          -- correct Host header when preserve_host = true and no registered
          -- API has a `hosts` property.

          local use_case_apis = {
            {
              name          = "no-host",
              uris          = { "/nohost" },
              preserve_host = true,
            }
          }

          local router = assert(Router.new(use_case_apis))

          local _ngx = mock_ngx("GET", "/nohost", { ["host"] = "domain1.com" })

          local match_t = router.exec(_ngx)
          assert.same(use_case_apis[1], match_t.api)
          assert.equal("domain1.com", match_t.upstream_host)

          _ngx = mock_ngx("GET", "/nohost", { ["host"] = "domain2.com" })

          match_t = router.exec(_ngx)
          assert.same(use_case_apis[1], match_t.api)
          assert.equal("domain2.com", match_t.upstream_host)
        end)
      end)

      describe("when preserve_host is false", function()
        local host = "discard.com"

        it("does not change the target upstream", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host })

          local match_t = router.exec(_ngx)
          assert.same(use_case_apis[2], match_t.api)
          assert.equal("example.org", match_t.upstream_url_t.host)
        end)

        it("does not set the host_header", function()
          local _ngx = mock_ngx("GET", "/", { ["host"] = host })

          local match_t = router.exec(_ngx)
          assert.same(use_case_apis[2], match_t.api)
          assert.is_nil(match_t.upstream_host)
        end)
      end)
    end)

    describe("trailing slash", function()
      local checks = {
        -- upstream url    uris            request path    expected path           strip uri
        {  "/",            "/",            "/",            "/",                    true      },
        {  "/",            "/",            "/foo/bar",     "/foo/bar",             true      },
        {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            true      },
        {  "/",            "/foo/bar",     "/foo/bar",     "/",                    true      },
        {  "/",            "/foo/bar/",    "/foo/bar/",    "/",                    true      },
        {  "/foo/bar",     "/",            "/",            "/foo/bar",             true      },
        {  "/foo/bar",     "/",            "/foo/bar",     "/foo/bar/foo/bar",     true      },
        {  "/foo/bar",     "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    true      },
        {  "/foo/bar",     "/foo/bar",     "/foo/bar",     "/foo/bar",             true      },
        {  "/foo/bar",     "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            true      },
        {  "/foo/bar/",    "/",            "/",            "/foo/bar/",            true      },
        {  "/foo/bar/",    "/",            "/foo/bar",     "/foo/bar/foo/bar",     true      },
        {  "/foo/bar/",    "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    true      },
        {  "/foo/bar/",    "/foo/bar",     "/foo/bar",     "/foo/bar",             true      },
        {  "/foo/bar/",    "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            true      },
        {  "/",            "/",            "/",            "/",                    false     },
        {  "/",            "/",            "/foo/bar",     "/foo/bar",             false     },
        {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            false     },
        {  "/",            "/foo/bar",     "/foo/bar",     "/foo/bar",             false     },
        {  "/",            "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            false     },
        {  "/foo/bar",     "/",            "/",            "/foo/bar",             false     },
        {  "/foo/bar",     "/",            "/foo/bar",     "/foo/bar/foo/bar",     false     },
        {  "/foo/bar",     "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    false     },
        {  "/foo/bar",     "/foo/bar",     "/foo/bar",     "/foo/bar/foo/bar",     false     },
        {  "/foo/bar",     "/foo/bar/",    "/foo/bar/",    "/foo/bar/foo/bar/",    false     },
        {  "/foo/bar/",    "/",            "/",            "/foo/bar/",            false     },
        {  "/foo/bar/",    "/",            "/foo/bar",     "/foo/bar/foo/bar",     false     },
        {  "/foo/bar/",    "/",            "/foo/bar/",    "/foo/bar/foo/bar/",    false     },
        {  "/foo/bar/",    "/foo/bar",     "/foo/bar",     "/foo/bar/foo/bar",     false     },
        {  "/foo/bar/",    "/foo/bar/",    "/foo/bar/",    "/foo/bar/foo/bar/",    false     },
      }

      for i, args in ipairs(checks) do

        local config = args[5] == true and "(strip_uri = on)" or "(strip_uri = off)"

        it(config .. " is not appended to upstream url " .. args[1] ..
                     " (with uri "                       .. args[2] .. ")" ..
                     " when requesting "                 .. args[3], function()


          local use_case_apis = {
            {
              name         = "api-1",
              strip_uri    = args[5],
              upstream_url = "http://example.org" .. args[1],
              uris         = {
                args[2],
              },
            }
          }

          local router = assert(Router.new(use_case_apis) )

          local _ngx = mock_ngx("GET", args[3], { ["host"] = "domain.org" })
          local match_t = router.exec(_ngx)
          assert.same(use_case_apis[1], match_t.api)
          assert.equal(args[1], match_t.upstream_url_t.path)
          assert.equal(args[4], match_t.upstream_uri)
        end)
      end
    end)
  end)

  describe("has_capturing_groups()", function()
    -- load the `assert.fail` assertion
    require "spec.helpers"

    it("detects if a string has capturing groups", function()
      local uris                         = {
        ["/users/(foo)"]                 = true,
        ["/users/()"]                    = true,
        ["/users/()/foo"]                = true,
        ["/users/(hello(foo)world)"]     = true,
        ["/users/(hello(foo)world"]      = true,
        ["/users/(foo)/thing/(bar)"]     = true,
        ["/users/\\(foo\\)/thing/(bar)"] = true,
        -- 0-indexed capture groups
        ["()/world"]                     = true,
        ["(/hello)/world"]               = true,

        ["/users/\\(foo\\)"] = false,
        ["/users/\\(\\)"]    = false,
        -- unbalanced capture groups
        ["(/hello\\)/world"] = false,
        ["/users/(foo"]      = false,
        ["/users/\\(foo)"]   = false,
        ["/users/(foo\\)"]   = false,
      }

      for uri, expected_to_match in pairs(uris) do
        local has_captures = Router.has_capturing_groups(uri)
        if expected_to_match and not has_captures then
          assert.fail(uri, "has capturing groups that were not detected")

        elseif not expected_to_match and has_captures then
          assert.fail(uri, "has no capturing groups but false-positives " ..
                           "were detected")
        end
      end
    end)
  end)
end)
