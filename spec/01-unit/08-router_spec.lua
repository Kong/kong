local Router = require "kong.router"

local function reload_router()
  package.loaded["kong.router"] = nil
  Router = require "kong.router"
end

local service = {
  name = "service-invalid",
  protocol = "http",
}

local use_case = {

  -- 1. host
  {
    service = service,
    route   = {
    },
    headers = {
      host  = {
        "domain-1.org",
        "domain-2.org"
      },
    },
  },
  -- 2. method
  {
    service = service,
    route   = {
      methods = {
        "TRACE"
      },
    }
  },
  -- 3. uri
  {
    service = service,
    route   = {
      paths = {
        "/my-route"
      },
    }
  },
  -- 4. host + uri
  {
    service = service,
    route   = {
      paths = {
        "/route-4"
      },
    },
    headers = {
      host  = {
        "domain-1.org",
        "domain-2.org"
      },
    },
  },
  -- 5. host + method
  {
    service = service,
    route   = {
      methods = {
        "POST",
        "PUT",
        "PATCH"
      },
    },
    headers = {
      host  = {
        "domain-1.org",
        "domain-2.org"
      },
    },
  },
  -- 6. uri + method
  {
    service = service,
    route   = {
      methods = {
        "POST",
        "PUT",
        "PATCH",
      },
      paths   = {
        "/route-6"
      },
    }
  },
  -- 7. host + uri + method
  {
    service = service,
    route   = {
      methods = {
        "POST",
        "PUT",
        "PATCH",
      },
      paths   = {
        "/my-route-uri"
      },
    },
    headers = {
      host = {
        "domain-with-uri-1.org",
        "domain-with-uri-2.org"
      },
    },
  },
  -- 8. serviceless-route
  {
    route   = {
      paths = {
        "/serviceless"
      },
    }
  },
}

describe("Router", function()
  describe("new()", function()
    describe("[errors]", function()
      it("enforces args types", function()
        assert.error_matches(function()
          Router.new()
        end, "expected arg #1 routes to be a table", nil, true)
      end)

      it("enforces routes fields types", function()
        local router, err = Router.new {
          {
            route   = {
            },
            service = {
              name  = "service-invalid"
            },
          },
        }

        assert.is_nil(router)
        assert.equal("could not categorize route", err)
      end)
    end)
  end)

  describe("select()", function()
    local router = assert(Router.new(use_case))

    it("[host]", function()
      -- host
      local match_t = router.select("GET", "/", "domain-1.org")
      assert.truthy(match_t)
      assert.same(use_case[1].route,   match_t.route)
      assert.same(match_t.matches.host, use_case[1].headers.host[1])
      assert.same(match_t.matches.method, nil)
      assert.same(match_t.matches.uri, nil)
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[host] ignores port", function()
      -- host
      local match_t = router.select("GET", "/", "domain-1.org:123")
      assert.truthy(match_t)
      assert.same(use_case[1].route, match_t.route)
      assert.same(match_t.matches.host, use_case[1].headers.host[1])
      assert.same(match_t.matches.method, nil)
      assert.same(match_t.matches.uri, nil)
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[uri]", function()
      -- uri
      local match_t = router.select("GET", "/my-route", "domain.org")
      assert.truthy(match_t)
      assert.same(use_case[3].route, match_t.route)
      assert.same(match_t.matches.host, nil)
      assert.same(match_t.matches.method, nil)
      assert.same(match_t.matches.uri, use_case[3].route.paths[1])
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[uri + empty host]", function()
      -- uri only (no Host)
      -- Supported for HTTP/1.0 requests without a Host header
      local match_t = router.select("GET", "/my-route-uri", "")
      assert.truthy(match_t)
      assert.same(use_case[3].route, match_t.route)
      assert.same(match_t.matches.host, nil)
      assert.same(match_t.matches.method, nil)
      assert.same(match_t.matches.uri, use_case[3].route.paths[1])
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[method]", function()
      -- method
      local match_t = router.select("TRACE", "/", "domain.org")
      assert.truthy(match_t)
      assert.same(use_case[2].route, match_t.route)
      assert.same(match_t.matches.host, nil)
      assert.same(match_t.matches.method, use_case[2].route.methods[1])
      assert.same(match_t.matches.uri, nil)
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[host + uri]", function()
      -- host + uri
      local match_t = router.select("GET", "/route-4", "domain-1.org")
      assert.truthy(match_t)
      assert.same(use_case[4].route, match_t.route)
      assert.same(match_t.matches.host, use_case[4].headers.host[1])
      assert.same(match_t.matches.method, nil)
      assert.same(match_t.matches.uri, use_case[4].route.paths[1])
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[host + method]", function()
      -- host + method
      local match_t = router.select("POST", "/", "domain-1.org")
      assert.truthy(match_t)
      assert.same(use_case[5].route, match_t.route)
      assert.same(match_t.matches.host, use_case[5].headers.host[1])
      assert.same(match_t.matches.method, use_case[5].route.methods[1])
      assert.same(match_t.matches.uri, nil)
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[uri + method]", function()
      -- uri + method
      local match_t = router.select("PUT", "/route-6", "domain.org")
      assert.truthy(match_t)
      assert.same(use_case[6].route, match_t.route)
      assert.same(match_t.matches.host, nil)
      assert.same(match_t.matches.method, use_case[6].route.methods[2])
      assert.same(match_t.matches.uri, use_case[6].route.paths[1])
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[host + uri + method]", function()
      -- uri + method
      local match_t = router.select("PUT", "/my-route-uri",
                                    "domain-with-uri-2.org")
      assert.truthy(match_t)
      assert.same(use_case[7].route, match_t.route)
      assert.same(match_t.matches.host, use_case[7].headers.host[2])
      assert.same(match_t.matches.method, use_case[7].route.methods[2])
      assert.same(match_t.matches.uri, use_case[7].route.paths[1])
      assert.same(match_t.matches.uri_captures, nil)
    end)

    it("[serviceless]", function()
      local match_t = router.select("GET", "/serviceless")
      assert.truthy(match_t)
      assert.is_nil(match_t.service)
      assert.is_nil(match_t.matches.uri_captures)
      assert.same(use_case[8].route, match_t.route)
      assert.same(match_t.matches.uri, use_case[8].route.paths[1])
    end)

    describe("[uri prefix]", function()
      it("matches when given [uri] is in request URI prefix", function()
        -- uri prefix
        local match_t = router.select("GET", "/my-route/some/path", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[3].route, match_t.route)
        assert.same(match_t.matches.host, nil)
        assert.same(match_t.matches.method, nil)
        assert.same(match_t.matches.uri, use_case[3].route.paths[1])
        assert.same(match_t.matches.uri_captures, nil)
      end)

      it("does not supersede another route with a longer [uri]", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { "/my-route/hello" },
            },
          },
          {
            service = service,
            route   = {
              paths = { "/my-route" },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/my-route/hello", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        assert.same(match_t.matches.uri, "/my-route/hello")

        match_t = router.select("GET", "/my-route/hello/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        assert.same(match_t.matches.uri, "/my-route/hello")

        match_t = router.select("GET", "/my-route", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
        assert.same(match_t.matches.uri, "/my-route")

        match_t = router.select("GET", "/my-route/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
        assert.same(match_t.matches.uri, "/my-route")
      end)

      it("does not supersede another route with a longer [uri] while [methods] are also defined", function()
        local use_case = {
          {
            service   = service,
            route     = {
              methods = { "POST", "PUT", "GET" },
              paths   = { "/my-route" },
            },
          },
          {
            service   = service,
            route     = {
              methods = { "POST", "PUT", "GET" },
              paths   = { "/my-route/hello" },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/my-route/hello", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)

        match_t = router.select("GET", "/my-route/hello/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)

        match_t = router.select("GET", "/my-route", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select("GET", "/my-route/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
      end)

      it("does not superseds another route with a longer [uri] while [hosts] are also defined", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { "/my-route" },
            },
            headers = {
              host  = { "domain.org" },
            },
          },
          {
            service = service,
            route   = {
              paths = { "/my-route/hello" },
            },
            headers = {
              host  = { "domain.org" },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/my-route/hello", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)

        match_t = router.select("GET", "/my-route/hello/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)

        match_t = router.select("GET", "/my-route", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select("GET", "/my-route/world", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
      end)

      it("only matches [uri prefix] as a prefix (anchored mode)", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { "/something/my-route" },
            },
          },
          {
            service = service,
            route   = {
              paths = { "/my-route" },
            },
            headers = {
              host  = { "example.com" },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/something/my-route", "example.com")
        assert.truthy(match_t)
        -- would be route-2 if URI matching was not prefix-only (anchored mode)
        assert.same(use_case[1].route, match_t.route)
        assert.same(match_t.matches.uri, "/something/my-route")
      end)
    end)

    describe("[uri regex]", function()
      it("matches with [uri regex]", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { [[/users/\d+/profile]] },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/users/123/profile", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        assert.same(match_t.matches.host, nil)
        assert.same(match_t.matches.method, nil)
        assert.same(match_t.matches.uri, [[/users/\d+/profile]])
        assert.same(match_t.matches.uri_captures, nil)
      end)

      it("matches the right route when several ones have a [uri regex]", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { [[/route/persons/\d{3}]] },
            },
          },
          {
            service = service,
            route   = {
              paths = { [[/route/persons/\d{3}/following]] },
            },
          },
          {
            service = service,
            route   = {
              paths = { [[/route/persons/\d{3}/[a-z]+]] },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/route/persons/456", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
      end)

      it("matches a [uri regex] even if a [prefix uri] got a match", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { [[/route/persons]] },
            },
          },
          {
            service = service,
            route   = {
              paths = { [[/route/persons/\d+/profile]] },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/route/persons/123/profile",
                                      "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
        assert.same(match_t.matches.host, nil)
        assert.same(match_t.matches.method, nil)
        assert.same(match_t.matches.uri, [[/route/persons/\d+/profile]])
        assert.same(match_t.matches.uri_captures, nil)
      end)
    end)

    describe("[wildcard host]", function()
      local use_case = {
        {
          service = service,
          route   = {
          },
          headers = {
            host  = { "*.route.com" },
          },
        },
        {
          service = service,
          route   = {
          },
          headers = {
            host  = { "route.*" },
          },
        },
      }

      local router = assert(Router.new(use_case))

      it("matches leftmost wildcards", function()
        local match_t = router.select("GET", "/", "foo.route.com", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        assert.same(match_t.matches.host, use_case[1].headers.host[1])
        assert.same(match_t.matches.method, nil)
        assert.same(match_t.matches.uri, nil)
        assert.same(match_t.matches.uri_captures, nil)
      end)

      it("matches rightmost wildcards", function()
        local match_t = router.select("GET", "/", "route.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      it("does not take precedence over a plain host", function()
        table.insert(use_case, 1, {
          service = service,
          route   = {
          },
          headers = {
            host  = { "plain.route.com" },
          },
        })

        table.insert(use_case, {
          service = service,
          route   = {
          },
          headers = {
            host  = { "route.com" },
          },
        })

        finally(function()
          table.remove(use_case, 1)
          table.remove(use_case)
          router = assert(Router.new(use_case))
        end)

        router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/", "route.com")
        assert.truthy(match_t)
        assert.same(use_case[4].route, match_t.route)
        assert.same(match_t.matches.host, "route.com")
        assert.same(match_t.matches.method, nil)
        assert.same(match_t.matches.uri, nil)
        assert.same(match_t.matches.uri_captures, nil)

        match_t = router.select("GET", "/", "route.org")
        assert.truthy(match_t)
        assert.same(use_case[3].route, match_t.route)
        assert.same(match_t.matches.host, "route.*")
        assert.same(match_t.matches.method, nil)
        assert.same(match_t.matches.uri, nil)
        assert.same(match_t.matches.uri_captures, nil)

        match_t = router.select("GET", "/", "plain.route.com")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        assert.same(match_t.matches.host, "plain.route.com")
        assert.same(match_t.matches.method, nil)
        assert.same(match_t.matches.uri, nil)
        assert.same(match_t.matches.uri_captures, nil)

        match_t = router.select("GET", "/", "foo.route.com")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
        assert.same(match_t.matches.host, "*.route.com")
        assert.same(match_t.matches.method, nil)
        assert.same(match_t.matches.uri, nil)
        assert.same(match_t.matches.uri_captures, nil)
      end)

      it("matches [wildcard/plain + uri + method]", function()
        finally(function()
          table.remove(use_case)
          router = assert(Router.new(use_case))
        end)

        table.insert(use_case, {
          service   = service,
          route     = {
            paths   = { "/path" },
            methods = { "GET", "TRACE" },
          },
          headers   = {
            host    = { "*.domain.com", "example.com" },
          },
        })

        router = assert(Router.new(use_case))

        local match_t = router.select("POST", "/path", "foo.domain.com")
        assert.is_nil(match_t)

        match_t = router.select("GET", "/path", "foo.domain.com")
        assert.truthy(match_t)
        assert.same(use_case[#use_case].route, match_t.route)

        match_t = router.select("TRACE", "/path", "example.com")
        assert.truthy(match_t)
        assert.same(use_case[#use_case].route, match_t.route)

        match_t = router.select("POST", "/path", "foo.domain.com")
        assert.is_nil(match_t)
      end)
    end)

    describe("[wildcard host] + [uri regex]", function()
      it("matches", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { [[/users/\d+/profile]] },
            },
            headers = {
              host  = { "*.example.com" },
            },
          },
          {
            service = service,
            route   = {
              paths = { [[/users]] },
            },
            headers = {
              host  = { "*.example.com" },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/users/123/profile",
                                      "test.example.com")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select("GET", "/users", "test.example.com")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)
    end)

    describe("edge-cases", function()
      it("[host] and [uri] have higher priority than [method]", function()
        -- host
        local match_t = router.select("TRACE", "/", "domain-2.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        -- uri
        local match_t = router.select("TRACE", "/my-route", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[3].route, match_t.route)
      end)

      it("half [uri] and [host] match does not supersede another route", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { "/v1/path" },
            },
            headers = {
              host  = { "host1.com" },
            },
          },
          {
            service = service,
            route   = {
              paths = { "/" },
            },
            headers = {
              host  = { "host2.com" },
            },
          },
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/v1/path", "host1.com")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select("GET", "/v1/path", "host2.com")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      it("half [wildcard host] and [method] match does not supersede another route", function()
        local use_case = {
          {
            service   = service,
            route     = {
              methods = { "GET" },
            },
            headers   = {
              host    = { "host.*" },
            },
          },
          {
            service   = service,
            route     = {
              methods = { "POST" },
            },
            headers   = {
              host    = { "host.*" },
            },
          },
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/", "host.com")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select("POST", "/", "host.com")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      it("half [uri regex] and [method] match does not supersede another route", function()
        local use_case = {
          {
            service   = service,
            route     = {
              methods = { "GET" },
              paths   = { [[/users/\d+/profile]] },
            },
          },
          {
            service   = service,
            route     = {
              methods = { "POST" },
              paths   = { [[/users/\d*/profile]] },
            },
          },
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/users/123/profile", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select("POST", "/users/123/profile", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      it("[method] does not supersede [uri prefix]", function()
        local use_case = {
          {
            service   = service,
            route     = {
              methods = { "GET" },
            },
          },
          {
            service   = service,
            route     = {
              paths   = { "/example" },
            },
          },
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/example", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)

        match_t = router.select("GET", "/example/status/200", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      it("[method] does not supersede [wildcard host]", function()
        local use_case = {
          {
            service    = service,
            route      = {
              methods  = { "GET" },
            },
          },
          {
            service    = service,
            route      = {
            },
            headers    = {
              ["Host"] = { "domain.*" },
            },
          },
        }

        local router = assert(Router.new(use_case))
        local match_t = router.select("GET", "/", "nothing.com")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select("GET", "/", "domain.com")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      it("does not supersede another route with a longer [uri prefix]", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { "/a", "/bbbbbbb" },
            },
          },
          {
            service = service,
            route   = {
              paths = { "/a/bb" },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local match_t = router.select("GET", "/a/bb/foobar", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      describe("root / [uri]", function()
        lazy_setup(function()
          table.insert(use_case, 1, {
            service = service,
            route   = {
              paths = { "/" },
            }
          })
        end)

        lazy_teardown(function()
          table.remove(use_case, 1)
        end)

        it("request with [method]", function()
          local router = assert(Router.new(use_case))
          local match_t = router.select("GET", "/", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
        end)

        it("does not supersede another route", function()
          local router = assert(Router.new(use_case))
          local match_t = router.select("GET", "/my-route", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[4].route, match_t.route)

          match_t = router.select("GET", "/my-route/hello/world", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[4].route, match_t.route)
        end)

        it("acts as a catch-all route", function()
          local router = assert(Router.new(use_case))
          local match_t = router.select("GET", "/foobar/baz", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
        end)
      end)

      describe("multiple routes of same category with conflicting values", function()
        -- reload router to reset combined cached matchers
        reload_router()

        local n = 6

        lazy_setup(function()
          -- all those routes are of the same category:
          -- [host + uri]
          for _ = 1, n - 1 do
            table.insert(use_case, {
              service = service,
              route   = {
                paths = { "/my-uri" },
              },
              headers = {
                host  = { "domain.org" },
              },
            })
          end

          table.insert(use_case, {
            service = service,
            route   = {
              paths = { "/my-target-uri" },
            },
            headers = {
              host  = { "domain.org" },
            },
          })
        end)

        lazy_teardown(function()
          for _ = 1, n do
            table.remove(use_case)
          end
        end)

        it("matches correct route", function()
          local router = assert(Router.new(use_case))
          local match_t = router.select("GET", "/my-target-uri", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[#use_case].route, match_t.route)
        end)
      end)

      it("does not incorrectly match another route which has a longer [uri]", function()
        local use_case = {
          {
            service = service,
            route   = {
              paths = { "/a", "/bbbbbbb" },
            },
          },
          {
            service = service,
            route   = {
              paths = { "/a/bb" },
            },
          },
        }

        local router = assert(Router.new(use_case))

        local route_t = router.select("GET", "/a/bb/foobar", "domain.org")
        assert.truthy(route_t)
        assert.same(use_case[2].route, route_t.route)
      end)
    end)

    describe("misses", function()
      it("invalid [host]", function()
        assert.is_nil(router.select("GET", "/", "domain-3.org"))
      end)

      it("invalid host in [host + uri]", function()
        assert.is_nil(router.select("GET", "/route-4", "domain-3.org"))
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
        local match_t = router.select("GET", "/some-other-prefix/my-route",
                                      "domain.org")
        assert.is_nil(match_t)
      end)
    end)

    describe("#benchmarks", function()
      --[[
        Run:
            $ busted --tags=benchmarks <router_spec.lua>

        To estimate how much time matching an route in a worst-case scenario
        with a set of ~1000 registered routes would take.

        We are aiming at sub-ms latency.
      ]]

      describe("plain [host]", function()
        local router
        local target_domain
        local benchmark_use_cases = {}

        lazy_setup(function()
          for i = 1, 10^5 do
            benchmark_use_cases[i] = {
              service = service,
              route   = {
              },
              headers = {
                host  = { "domain-" .. i .. ".org" },
              },
            }
          end

          target_domain = "domain-" .. #benchmark_use_cases .. ".org"
          router = assert(Router.new(benchmark_use_cases))
        end)

        it("takes < 1ms", function()
          local match_t = router.select("GET", "/", target_domain)
          assert.truthy(match_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases].route, match_t.route)
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
            -- insert a lot of routes that don't match (missing methods)
            -- but have conflicting paths and hosts (domain-<n>.org)

            benchmark_use_cases[i] = {
              service = service,
              route   = {
                paths = { "/my-route-" .. n },
              },
              headers = {
                host  = { "domain-" .. n .. ".org" },
              },
            }
          end

          -- insert our target route, which has the proper method as well
          benchmark_use_cases[n] = {
            service   = service,
            route     = {
              methods = { "POST" },
              paths   = { "/my-route-" .. n },
            },
            headers   = {
              host    = { "domain-" .. n .. ".org" },
            },
          }

          target_uri = "/my-route-" .. n
          target_domain = "domain-" .. n .. ".org"
          router = assert(Router.new(benchmark_use_cases))
        end)

        it("takes < 1ms", function()
          local match_t = router.select("POST", target_uri, target_domain)
          assert.truthy(match_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases].route, match_t.route)
        end)
      end)

      describe("multiple routes of same category with identical values", function()
        local router
        local target_uri
        local target_domain
        local benchmark_use_cases = {}

        lazy_setup(function()
          local n = 10^5

          for i = 1, n - 1 do
            -- all our routes here use domain.org as the domain
            -- they all are [host + uri] category
            benchmark_use_cases[i] = {
              service = service,
              route   = {
                paths = { "/my-route-" .. n },
              },
              headers = {
                host  = { "domain.org" },
              },
            }
          end

          -- this one too, but our target will be a
          -- different URI
          benchmark_use_cases[n] = {
            service = service,
            route   = {
              paths = { "/my-real-route" },
            },
            headers = {
              host  = { "domain.org" },
            },
          }

          target_uri = "/my-real-route"
          target_domain = "domain.org"
          router = assert(Router.new(benchmark_use_cases))
        end)

        it("takes < 1ms", function()
          local match_t = router.select("GET", target_uri, target_domain)
          assert.truthy(match_t)
          assert.same(benchmark_use_cases[#benchmark_use_cases].route, match_t.route)
        end)
      end)
    end)

    describe("[errors]", function()
      it("enforces args types", function()
        assert.error_matches(function()
          router.select(1)
        end, "method must be a string", nil, true)

        assert.error_matches(function()
          router.select("GET", 1)
        end, "uri must be a string", nil, true)

        assert.error_matches(function()
          router.select("GET", "/", 1)
        end, "host must be a string", nil, true)
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

    it("returns parsed upstream_url + upstream_uri", function()
      local use_case_routes = {
        {
          service    = {
            name     = "service-invalid",
            host     = "example.org",
            protocol = "http"
          },
          route      = {
            paths    = { "/my-route" },
          },
        },
        {
          service    = {
            name     = "service-invalid",
            host     = "example.org",
            protocol = "https"
          },
          route      = {
            paths    = { "/my-route-2" },
          },
        },
      }

      local router = assert(Router.new(use_case_routes))
      local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
      assert.same(use_case_routes[1].route, match_t.route)

      -- upstream_url_t
      assert.equal("http", match_t.upstream_url_t.scheme)
      assert.equal("example.org", match_t.upstream_url_t.host)
      assert.equal(80, match_t.upstream_url_t.port)

      -- upstream_uri
      assert.is_nil(match_t.upstream_host) -- only when `preserve_host = true`
      assert.equal("/my-route", match_t.upstream_uri)

      _ngx = mock_ngx("GET", "/my-route-2", { host = "domain.org" })
      router._set_ngx(_ngx)
      match_t = router.exec()
      assert.same(use_case_routes[2].route, match_t.route)

      -- upstream_url_t
      assert.equal("https", match_t.upstream_url_t.scheme)
      assert.equal("example.org", match_t.upstream_url_t.host)
      assert.equal(443, match_t.upstream_url_t.port)

      -- upstream_uri
      assert.is_nil(match_t.upstream_host) -- only when `preserve_host = true`
      assert.equal("/my-route-2", match_t.upstream_uri)
    end)

    it("returns matched_host + matched_uri + matched_method", function()
      local use_case_routes = {
        {
          service   = service,
          route     = {
            methods = { "GET" },
            paths   = { "/my-route" },
          },
          headers   = {
            host    = { "host.com" },
          },
        },
        {
          service   = service,
          route     = {
            paths   = { "/my-route" },
          },
          headers   = {
            host    = { "host.com" },
          },
        },
        {
          service   = service,
          route     = {
          },
          headers   = {
            host    = { "*.host.com" },
          },
        },
        {
          service   = service,
          route     = {
            paths   = { [[/users/\d+/profile]] },
          },
        },
      }

      local router = assert(Router.new(use_case_routes))
      local _ngx = mock_ngx("GET", "/my-route", { host = "host.com" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
      assert.same(use_case_routes[1].route, match_t.route)
      assert.equal("host.com", match_t.matches.host)
      assert.equal("/my-route", match_t.matches.uri)
      assert.equal("GET", match_t.matches.method)

      _ngx = mock_ngx("GET", "/my-route/prefix/match", { host = "host.com" })
      router._set_ngx(_ngx)
      match_t = router.exec()
      assert.same(use_case_routes[1].route, match_t.route)
      assert.equal("host.com", match_t.matches.host)
      assert.equal("/my-route", match_t.matches.uri)
      assert.equal("GET", match_t.matches.method)

      _ngx = mock_ngx("POST", "/my-route", { host = "host.com" })
      router._set_ngx(_ngx)
      match_t = router.exec()
      assert.same(use_case_routes[2].route, match_t.route)
      assert.equal("host.com", match_t.matches.host)
      assert.equal("/my-route", match_t.matches.uri)
      assert.is_nil(match_t.matches.method)

      _ngx = mock_ngx("GET", "/", { host = "test.host.com" })
      router._set_ngx(_ngx)
      match_t = router.exec()
      assert.same(use_case_routes[3].route, match_t.route)
      assert.equal("*.host.com", match_t.matches.host)
      assert.is_nil(match_t.matches.uri)
      assert.is_nil(match_t.matches.method)

      _ngx = mock_ngx("GET", "/users/123/profile", { host = "domain.org" })
      router._set_ngx(_ngx)
      match_t = router.exec()
      assert.same(use_case_routes[4].route, match_t.route)
      assert.is_nil(match_t.matches.host)
      assert.equal([[/users/\d+/profile]], match_t.matches.uri)
      assert.is_nil(match_t.matches.method)
    end)

    it("returns uri_captures from a [uri regex]", function()
      local use_case = {
        {
          service = service,
          route   = {
            paths = { [[/users/(?P<user_id>\d+)/profile/?(?P<scope>[a-z]*)]] },
          },
        },
      }

      local router = assert(Router.new(use_case))
      local _ngx = mock_ngx("GET", "/users/1984/profile",
                            { host = "domain.org" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
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
      router._set_ngx(_ngx)
      match_t = router.exec()
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
                      { host = "domain.org" })
      router._set_ngx(_ngx)
      match_t = router.exec()
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
          service      = service,
          route        = {
            paths      = { "/hello" },
            strip_path = true,
          },
        },
      }

      local router = assert(Router.new(use_case))
      local _ngx = mock_ngx("GET", "/hello/world", { host = "domain.org" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
      assert.equal("/world", match_t.upstream_uri)
      assert.is_nil(match_t.matches.uri_captures)
    end)

    it("returns no uri_captures from a [uri regex] match without groups", function()
      local use_case = {
        {
          service = service,
          route   = {
            paths = { [[/users/\d+/profile]] },
          },
        },
      }

      local router = assert(Router.new(use_case))
      local _ngx = mock_ngx("GET", "/users/1984/profile",
                            { host = "domain.org" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
      assert.is_nil(match_t.matches.uri_captures)
    end)

    it("parses path component from upstream_url property", function()
      local use_case_routes = {
        {
          service    = {
            name     = "service-invalid",
            host     = "example.org",
            path     = "/get",
            protocol = "http"
          },
          route      = {
            paths    = { "/my-route" },
          },
        },
      }

      local router = assert(Router.new(use_case_routes))
      local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
      assert.same(use_case_routes[1].route, match_t.route)
      assert.equal("/get", match_t.upstream_url_t.path)
    end)

    it("parses upstream_url port", function()
      local use_case_routes = {
        {
          service    = {
            name     = "service-invalid",
            host     = "example.org",
            port     = 8080,
            protocol = "http"
          },
          route      = {
            paths    = { "/my-route" },
          },
        },
        {
          service = {
            name     = "service-invalid",
            host     = "example.org",
            port     = 8443,
            protocol = "https"
          },
          route      = {
            paths    = { "/my-route-2" },
          },
        },
      }

      local router = assert(Router.new(use_case_routes))
      local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
      assert.equal(8080, match_t.upstream_url_t.port)

      _ngx = mock_ngx("GET", "/my-route-2", { host = "domain.org" })
      router._set_ngx(_ngx)
      match_t = router.exec()
      assert.equal(8443, match_t.upstream_url_t.port)
    end)

    it("allows url encoded paths", function()
      local use_case_routes = {
        {
          service = service,
          route   = {
            paths = { "/endel%C3%B8st" },
          },
        },
      }

      local router = assert(Router.new(use_case_routes))
      local _ngx = mock_ngx("GET", "/endel%C3%B8st", { host = "domain.org" })
      router._set_ngx(_ngx)
      local match_t = router.exec()
      assert.same(use_case_routes[1].route, match_t.route)
      assert.equal("/endel%C3%B8st", match_t.upstream_uri)
    end)

    describe("stripped paths", function()
      local router
      local use_case_routes = {
        {
          service      = service,
          route        = {
            paths      = { "/my-route", "/this-route" },
            strip_path = true
          }
        },
        -- don't strip this route's matching URI
        {
          service      = service,
          route        = {
            methods    = { "POST" },
            paths      = { "/my-route", "/this-route" },
          },
        },
      }

      lazy_setup(function()
        router = assert(Router.new(use_case_routes))
      end)

      it("strips the specified paths from the given uri if matching", function()
        local _ngx = mock_ngx("GET", "/my-route/hello/world",
                              { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/hello/world", match_t.upstream_uri)
      end)

      it("strips if matched URI is plain (not a prefix)", function()
        local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/", match_t.upstream_uri)
      end)

      it("doesn't strip if 'strip_uri' is not enabled", function()
        local _ngx = mock_ngx("POST", "/my-route/hello/world",
                              { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.same(use_case_routes[2].route, match_t.route)
        assert.equal("/my-route/hello/world", match_t.upstream_uri)
      end)

      it("does not strips root / URI", function()
        local use_case_routes = {
          {
            service      = service,
            route        = {
              paths      = { "/" },
              strip_path = true,
            },
          },
        }

        local router = assert(Router.new(use_case_routes))

        local _ngx = mock_ngx("POST", "/my-route/hello/world",
                              { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/my-route/hello/world", match_t.upstream_uri)
      end)

      it("can find an route with stripped URI several times in a row", function()
        local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/", match_t.upstream_uri)
      end)

      it("can proxy an route with stripped URI with different URIs in a row", function()
        local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/this-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/this-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/", match_t.upstream_uri)
      end)

      it("strips url encoded paths", function()
        local use_case_routes = {
          {
            service      = service,
            route        = {
              paths      = { "/endel%C3%B8st" },
              strip_path = true,
            },
          },
        }

        local router = assert(Router.new(use_case_routes))
        local _ngx = mock_ngx("GET", "/endel%C3%B8st", { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/", match_t.upstream_uri)
      end)

      it("strips a [uri regex]", function()
        local use_case = {
          {
            service      = service,
            route        = {
              paths      = { [[/users/\d+/profile]] },
              strip_path = true,
            },
          },
        }

        local router = assert(Router.new(use_case))
        local _ngx = mock_ngx("GET", "/users/123/profile/hello/world",
                              { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.equal("/hello/world", match_t.upstream_uri)
      end)

      it("strips a [uri regex] with a capture group", function()
        local use_case = {
          {
            service      = service,
            route        = {
              paths      = { [[/users/(\d+)/profile]] },
              strip_path = true,
            },
          },
        }

        local router = assert(Router.new(use_case))
        local _ngx = mock_ngx("GET", "/users/123/profile/hello/world",
                              { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router.exec()
        assert.equal("/hello/world", match_t.upstream_uri)
      end)
    end)

    describe("preserve Host header", function()
      local router
      local use_case_routes = {
        -- use the request's Host header
        {
          service         = {
            name          = "service-invalid",
            host          = "example.org",
            protocol      = "http"
          },
          route           = {
            preserve_host = true,
          },
          headers         = {
            host          = { "preserve.com" },
          },
        },
        -- use the route's upstream_url's Host
        {
          service         = {
            name          = "service-invalid",
            host          = "example.org",
            protocol      = "http"
          },
          route           = {
            preserve_host = false,
          },
          headers         = {
            host          = { "discard.com" },
          },
        },
      }

      lazy_setup(function()
        router = assert(Router.new(use_case_routes))
      end)

      describe("when preserve_host is true", function()
        local host = "preserve.com"

        it("uses the request's Host header", function()
          local _ngx = mock_ngx("GET", "/", { host = host })
          router._set_ngx(_ngx)
          local match_t = router.exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal(host, match_t.upstream_host)
        end)

        it("uses the request's Host header incl. port", function()
          local _ngx = mock_ngx("GET", "/", { host = host .. ":123" })
          router._set_ngx(_ngx)
          local match_t = router.exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal(host .. ":123", match_t.upstream_host)
        end)

        it("does not change the target upstream", function()
          local _ngx = mock_ngx("GET", "/", { host = host })
          router._set_ngx(_ngx)
          local match_t = router.exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("example.org", match_t.upstream_url_t.host)
        end)

        it("uses the request's Host header when `grab_header` is disabled", function()
          local use_case_routes = {
            {
              service         = service,
              route           = {
                name          = "route-1",
                preserve_host = true,
                paths         = { "/foo" },
              },
              upstream_url    = "http://example.org",
            },
          }

          local router = assert(Router.new(use_case_routes))
          local _ngx = mock_ngx("GET", "/foo", { host = "preserve.com" })
          router._set_ngx(_ngx)
          local match_t = router.exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("preserve.com", match_t.upstream_host)
        end)

        it("uses the request's Host header if an route with no host was cached", function()
          -- This is a regression test for:
          -- https://github.com/Kong/kong/issues/2825
          -- Ensure cached routes (in the LRU cache) still get proxied with the
          -- correct Host header when preserve_host = true and no registered
          -- route has a `hosts` property.

          local use_case_routes = {
            {
              service         = service,
              route           = {
                name          = "no-host",
                paths         = { "/nohost" },
                preserve_host = true,
              },
            },
          }

          local router = assert(Router.new(use_case_routes))
          local _ngx = mock_ngx("GET", "/nohost", { host = "domain1.com" })
          router._set_ngx(_ngx)
          local match_t = router.exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("domain1.com", match_t.upstream_host)

          _ngx = mock_ngx("GET", "/nohost", { host = "domain2.com" })
          router._set_ngx(_ngx)
          match_t = router.exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("domain2.com", match_t.upstream_host)
        end)
      end)

      describe("when preserve_host is false", function()
        local host = "discard.com"

        it("does not change the target upstream", function()
          local _ngx = mock_ngx("GET", "/", { host = host })
          router._set_ngx(_ngx)
          local match_t = router.exec()
          assert.same(use_case_routes[2].route, match_t.route)
          assert.equal("example.org", match_t.upstream_url_t.host)
        end)

        it("does not set the host_header", function()
          local _ngx = mock_ngx("GET", "/", { host = host })
          router._set_ngx(_ngx)
          local match_t = router.exec()
          assert.same(use_case_routes[2].route, match_t.route)
          assert.is_nil(match_t.upstream_host)
        end)
      end)
    end)


    describe("slash handling", function()
      local checks = {
        -- upstream url    paths           request path    expected path           strip uri
        {  "/",            "/",            "/",            "/",                    true      }, -- 1
        {  "/",            "/",            "/foo/bar",     "/foo/bar",             true      },
        {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            true      },
        {  "/",            "/foo/bar",     "/foo/bar",     "/",                    true      },
        {  "/",            "/foo/bar",     "/foo/bar/",    "/",                    true      },
        {  "/",            "/foo/bar/",    "/foo/bar/",    "/",                    true      },
        {  "/fee/bor",     "/",            "/",            "/fee/bor",             true      },
        {  "/fee/bor",     "/",            "/foo/bar",     "/fee/borfoo/bar",      true      },
        {  "/fee/bor",     "/",            "/foo/bar/",    "/fee/borfoo/bar/",     true      },
        {  "/fee/bor",     "/foo/bar",     "/foo/bar",     "/fee/bor",             true      }, -- 10
        {  "/fee/bor",     "/foo/bar",     "/foo/bar/",    "/fee/bor/",            true      },
        {  "/fee/bor",     "/foo/bar/",    "/foo/bar/",    "/fee/bor",             true      },
        {  "/fee/bor/",    "/",            "/",            "/fee/bor/",            true      },
        {  "/fee/bor/",    "/",            "/foo/bar",     "/fee/bor/foo/bar",     true      },
        {  "/fee/bor/",    "/",            "/foo/bar/",    "/fee/bor/foo/bar/",    true      },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bar",     "/fee/bor/",            true      },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bar/",    "/fee/bor/",            true      },
        {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/",    "/fee/bor/",            true      },
        {  "/",            "/",            "/",            "/",                    false     },
        {  "/",            "/",            "/foo/bar",     "/foo/bar",             false     }, -- 20
        {  "/",            "/",            "/foo/bar/",    "/foo/bar/",            false     },
        {  "/",            "/foo/bar",     "/foo/bar",     "/foo/bar",             false     },
        {  "/",            "/foo/bar",     "/foo/bar/",    "/foo/bar/",            false     },
        {  "/",            "/foo/bar/",    "/foo/bar/",    "/foo/bar/",            false     },
        {  "/fee/bor",     "/",            "/",            "/fee/bor",             false     },
        {  "/fee/bor",     "/",            "/foo/bar",     "/fee/borfoo/bar",      false     },
        {  "/fee/bor",     "/",            "/foo/bar/",    "/fee/borfoo/bar/",     false     },
        {  "/fee/bor",     "/foo/bar",     "/foo/bar",     "/fee/borfoo/bar",      false     },
        {  "/fee/bor",     "/foo/bar",     "/foo/bar/",    "/fee/borfoo/bar/",     false     },
        {  "/fee/bor",     "/foo/bar/",    "/foo/bar/",    "/fee/borfoo/bar/",     false     }, -- 30
        {  "/fee/bor/",    "/",            "/",            "/fee/bor/",            false     },
        {  "/fee/bor/",    "/",            "/foo/bar",     "/fee/bor/foo/bar",     false     },
        {  "/fee/bor/",    "/",            "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bar",     "/fee/bor/foo/bar",     false     },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
        {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
        -- the following block runs the same tests, but with a request path that is longer
        -- than the matched part, so either matches in the middle of a segment, or has an
        -- additional segment.
        {  "/",            "/",            "/foo/bars",    "/foo/bars",            true      },
        {  "/",            "/",            "/foo/bar/s",   "/foo/bar/s",           true      },
        {  "/",            "/foo/bar",     "/foo/bars",    "/s",                   true      },
        {  "/",            "/foo/bar/",    "/foo/bar/s",   "/s",                   true      }, -- 40
        {  "/fee/bor",     "/",            "/foo/bars",    "/fee/borfoo/bars",     true      },
        {  "/fee/bor",     "/",            "/foo/bar/s",   "/fee/borfoo/bar/s",    true      },
        {  "/fee/bor",     "/foo/bar",     "/foo/bars",    "/fee/bors",            true      },
        {  "/fee/bor",     "/foo/bar/",    "/foo/bar/s",   "/fee/bors",            true      },
        {  "/fee/bor/",    "/",            "/foo/bars",    "/fee/bor/foo/bars",    true      },
        {  "/fee/bor/",    "/",            "/foo/bar/s",   "/fee/bor/foo/bar/s",   true      },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bars",    "/fee/bor/s",           true      },
        {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/s",   "/fee/bor/s",           true      },
        {  "/",            "/",            "/foo/bars",    "/foo/bars",            false     },
        {  "/",            "/",            "/foo/bar/s",   "/foo/bar/s",           false     }, -- 50
        {  "/",            "/foo/bar",     "/foo/bars",    "/foo/bars",            false     },
        {  "/",            "/foo/bar/",    "/foo/bar/s",   "/foo/bar/s",           false     },
        {  "/fee/bor",     "/",            "/foo/bars",    "/fee/borfoo/bars",     false     },
        {  "/fee/bor",     "/",            "/foo/bar/s",   "/fee/borfoo/bar/s",    false     },
        {  "/fee/bor",     "/foo/bar",     "/foo/bars",    "/fee/borfoo/bars",     false     },
        {  "/fee/bor",     "/foo/bar/",    "/foo/bar/s",   "/fee/borfoo/bar/s",    false     },
        {  "/fee/bor/",    "/",            "/foo/bars",    "/fee/bor/foo/bars",    false     },
        {  "/fee/bor/",    "/",            "/foo/bar/s",   "/fee/bor/foo/bar/s",   false     },
        {  "/fee/bor/",    "/foo/bar",     "/foo/bars",    "/fee/bor/foo/bars",    false     },
        {  "/fee/bor/",    "/foo/bar/",    "/foo/bar/s",   "/fee/bor/foo/bar/s",   false     }, -- 60
        -- the following block matches on host, instead of path
        {  "/",            nil,            "/",            "/",                    false     },
        {  "/",            nil,            "/foo/bar",     "/foo/bar",             false     },
        {  "/",            nil,            "/foo/bar/",    "/foo/bar/",            false     },
        {  "/fee/bor",     nil,            "/",            "/fee/bor",             false     },
        {  "/fee/bor",     nil,            "/foo/bar",     "/fee/borfoo/bar",      false     },
        {  "/fee/bor",     nil,            "/foo/bar/",    "/fee/borfoo/bar/",     false     },
        {  "/fee/bor/",    nil,            "/",            "/fee/bor/",            false     },
        {  "/fee/bor/",    nil,            "/foo/bar",     "/fee/bor/foo/bar",     false     },
        {  "/fee/bor/",    nil,            "/foo/bar/",    "/fee/bor/foo/bar/",    false     },
        {  "/",            nil,            "/",            "/",                    true      }, -- 70
        {  "/",            nil,            "/foo/bar",     "/foo/bar",             true      },
        {  "/",            nil,            "/foo/bar/",    "/foo/bar/",            true      },
        {  "/fee/bor",     nil,            "/",            "/fee/bor",             true      },
        {  "/fee/bor",     nil,            "/foo/bar",     "/fee/borfoo/bar",      true      },
        {  "/fee/bor",     nil,            "/foo/bar/",    "/fee/borfoo/bar/",     true      },
        {  "/fee/bor/",    nil,            "/",            "/fee/bor/",            true      },
        {  "/fee/bor/",    nil,            "/foo/bar",     "/fee/bor/foo/bar",     true      },
        {  "/fee/bor/",    nil,            "/foo/bar/",    "/fee/bor/foo/bar/",    true      },
      }

      for i, args in ipairs(checks) do

        local config = args[5] == true and "(strip = on, plain)" or "(strip = off, plain)"

        it("(" .. i .. ") " .. config ..
           " is not appended to upstream url " .. args[1] ..
           " (with " .. (args[2] and ("uri " .. args[2]) or
           ("host test" .. i .. ".domain.org")) .. ")" ..
           " when requesting " .. args[3], function()


          local use_case_routes = {
            {
              service      = {
                protocol   = "http",
                name       = "service-invalid",
                path       = args[1],
              },
              route        = {
                strip_path = args[5],
                paths      = { args[2] },
              },
              headers   = {
                -- only add the header is no path is provided
                host    = args[2] == nil and nil or { "test" .. i .. ".domain.org" },
              },
            }
          }

          local router = assert(Router.new(use_case_routes) )
          local _ngx = mock_ngx("GET", args[3], { host = "test" .. i .. ".domain.org" })
          router._set_ngx(_ngx)
          local match_t = router.exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal(args[1], match_t.upstream_url_t.path)
          assert.equal(args[4], match_t.upstream_uri)
        end)
      end

      -- this is identical to the tests above, except that for the path we match
      -- with an injected regex sequence, effectively transforming the path
      -- match into a regex match
      local function make_a_regex(path)
        return "/[0]?" .. path:sub(2, -1)
      end

      for i, args in ipairs(checks) do
        local config = args[5] == true and "(strip = on, regex)" or "(strip = off, regex)"

        if args[2] then -- skip test cases which match on host
          it("(" .. i .. ") " .. config ..
            " is not appended to upstream url " .. args[1] ..
            " (with " .. (args[2] and ("uri " .. make_a_regex(args[2])) or
            ("host test" .. i .. ".domain.org")) .. ")" ..
            " when requesting " .. args[3], function()


            local use_case_routes = {
              {
                service      = {
                  protocol   = "http",
                  name       = "service-invalid",
                  path       = args[1],
                },
                route        = {
                  strip_path = args[5],
                  paths      = { make_a_regex(args[2]) },
                },
                headers   = {
                  -- only add the header is no path is provided
                  host    = args[2] == nil and nil or { "test" .. i .. ".domain.org" },
                },
              }
            }

            local router = assert(Router.new(use_case_routes) )
            local _ngx = mock_ngx("GET", args[3], { host = "test" .. i .. ".domain.org" })
            router._set_ngx(_ngx)
            local match_t = router.exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal(args[1], match_t.upstream_url_t.path)
            assert.equal(args[4], match_t.upstream_uri)
          end)
        end
      end
    end)
  end)


  describe("has_capturing_groups()", function()
    -- load the `assert.fail` assertion
    require "spec.helpers"

    it("detects if a string has capturing groups", function()
      local paths                         = {
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

        ["/users/\\(foo\\)"]             = false,
        ["/users/\\(\\)"]                = false,
        -- unbalanced capture groups
        ["(/hello\\)/world"]             = false,
        ["/users/(foo"]                  = false,
        ["/users/\\(foo)"]               = false,
        ["/users/(foo\\)"]               = false,
      }

      for uri, expected_to_match in pairs(paths) do
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


  describe("#stream context", function()
    describe("[sources]", function()
      local use_case = {
        -- plain
        {
          service = service,
          route = {
            sources = {
              { ip = "127.0.0.1" },
              { ip = "127.0.0.2" },
            }
          }
        },
        {
          service = service,
          route = {
            sources = {
              { port = 65001 },
              { port = 65002 },
            }
          }
        },
        -- range
        {
          service = service,
          route = {
            sources = {
              { ip = "127.168.0.0/8" },
            }
          }
        },
        -- ip + port
        {
          service = service,
          route = {
            sources = {
              { ip = "127.0.0.1", port = 65001 },
            }
          }
        },
        {
          service = service,
          route = {
            sources = {
              { ip = "127.0.0.2", port = 65300 },
              { ip = "127.168.0.0/16", port = 65301 },
            }
          }
        },
      }

      local router = assert(Router.new(use_case))

      it("[src_ip]", function()
        local match_t = router.select(nil, nil, nil, "127.0.0.1")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select(nil, nil, nil, "127.0.0.1")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
      end)

      it("[src_port]", function()
        local match_t = router.select(nil, nil, nil, "127.0.0.3", 65001)
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      it("[src_ip] range match", function()
        local match_t = router.select(nil, nil, nil, "127.168.0.1")
        assert.truthy(match_t)
        assert.same(use_case[3].route, match_t.route)
      end)

      it("[src_ip] + [src_port]", function()
        local match_t = router.select(nil, nil, nil, "127.0.0.1", 65001)
        assert.truthy(match_t)
        assert.same(use_case[4].route, match_t.route)
      end)

      it("[src_ip] range match + [src_port]", function()
        local match_t = router.select(nil, nil, nil, "127.168.10.1", 65301)
        assert.truthy(match_t)
        assert.same(use_case[5].route, match_t.route)
      end)

      it("[src_ip] no match", function()
        local match_t = router.select(nil, nil, nil, "10.0.0.1")
        assert.falsy(match_t)

        match_t = router.select(nil, nil, nil, "10.0.0.2", 65301)
        assert.falsy(match_t)
      end)
    end)


    describe("[destinations]", function()
      local use_case = {
        -- plain
        {
          service = service,
          route = {
            destinations = {
              { ip = "127.0.0.1" },
              { ip = "127.0.0.2" },
            }
          }
        },
        {
          service = service,
          route = {
            destinations = {
              { port = 65001 },
              { port = 65002 },
            }
          }
        },
        -- range
        {
          service = service,
          route = {
            destinations = {
              { ip = "127.168.0.0/8" },
            }
          }
        },
        -- ip + port
        {
          service = service,
          route = {
            destinations = {
              { ip = "127.0.0.1", port = 65001 },
            }
          }
        },
        {
          service = service,
          route = {
            destinations = {
              { ip = "127.0.0.2", port = 65300 },
              { ip = "127.168.0.0/16", port = 65301 },
            }
          }
        },
      }

      local router = assert(Router.new(use_case))

      it("[dst_ip]", function()
        local match_t = router.select(nil, nil, nil, nil, nil,
                                      "127.0.0.1")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)

        match_t = router.select(nil, nil, nil, nil, nil,
                                "127.0.0.1")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
      end)

      it("[dst_port]", function()
        local match_t = router.select(nil, nil, nil, nil, nil,
                                      "127.0.0.3", 65001)
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

      it("[dst_ip] range match", function()
        local match_t = router.select(nil, nil, nil, nil, nil,
                                      "127.168.0.1")
        assert.truthy(match_t)
        assert.same(use_case[3].route, match_t.route)
      end)

      it("[dst_ip] + [dst_port]", function()
        local match_t = router.select(nil, nil, nil, nil, nil,
                                      "127.0.0.1", 65001)
        assert.truthy(match_t)
        assert.same(use_case[4].route, match_t.route)
      end)

      it("[dst_ip] range match + [dst_port]", function()
        local match_t = router.select(nil, nil, nil, nil, nil,
                                      "127.168.10.1", 65301)
        assert.truthy(match_t)
        assert.same(use_case[5].route, match_t.route)
      end)

      it("[dst_ip] no match", function()
        local match_t = router.select(nil, nil, nil, nil, nil,
                                      "10.0.0.1")
        assert.falsy(match_t)

        match_t = router.select(nil, nil, nil, nil, nil,
                                "10.0.0.2", 65301)
        assert.falsy(match_t)
      end)
    end)


    describe("[snis]", function()
      local use_case = {
        {
          service = service,
          route = {
            snis = { "www.example.org" }
          }
        },
      }

      local router = assert(Router.new(use_case))

      it("[sni]", function()
        local match_t = router.select(nil, nil, nil, nil, nil, nil, nil,
                                      "www.example.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
      end)
    end)


    it("[sni] has higher priority than [src] or [dst]", function()
      local use_case = {
        {
          service = service,
          route = {
            snis = { "www.example.org" },
          }
        },
        {
          service = service,
          route = {
            sources = {
              { ip = "127.0.0.1" },
            }
          }
        },
        {
          service = service,
          route = {
            destinations = {
              { ip = "172.168.0.1" },
            }
          }
        },
      }

      local router = assert(Router.new(use_case))

      local match_t = router.select(nil, nil, nil, "127.0.0.1", nil,
                                    nil, nil, "www.example.org")
      assert.truthy(match_t)
      assert.same(use_case[1].route, match_t.route)

      match_t = router.select(nil, nil, nil, nil, nil,
                              "172.168.0.1", nil, "www.example.org")
      assert.truthy(match_t)
      assert.same(use_case[1].route, match_t.route)
    end)

    it("[src] + [dst] has higher priority than [sni]", function()
      local use_case = {
        {
          service = service,
          route = {
            snis = { "www.example.org" },
          }
        },
        {
          service = service,
          route = {
            sources = {
              { ip = "127.0.0.1" },
            },
            destinations = {
              { ip = "172.168.0.1" },
            }
          }
        },
      }

      local router = assert(Router.new(use_case))

      local match_t = router.select(nil, nil, nil, "127.0.0.1", nil,
                                    "172.168.0.1", nil, "www.example.org")
      assert.truthy(match_t)
      assert.same(use_case[2].route, match_t.route)
    end)
  end)
end)
