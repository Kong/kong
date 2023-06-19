local Router
local atc_compat = require "kong.router.compat"
local path_handling_tests = require "spec.fixtures.router_path_handling_tests"
local uuid = require("kong.tools.utils").uuid

local function reload_router(flavor, subsystem)
  _G.kong = {
    configuration = {
      router_flavor = flavor,
    },
  }

  ngx.config.subsystem = subsystem or "http" -- luacheck: ignore

  package.loaded["kong.router.atc"] = nil
  package.loaded["kong.router.compat"] = nil
  package.loaded["kong.router"] = nil

  Router = require "kong.router"
end

local function new_router(cases, old_router)
  -- add fields expression/priority only for flavor expressions
  if kong.configuration.router_flavor == "expressions" then
    for _, v in ipairs(cases) do
      local r = v.route

      r.expression = r.expression or atc_compat.get_expression(r)
      r.priority = r.priority or atc_compat._get_priority(r)
    end
  end

  return Router.new(cases, nil, nil, old_router)
end

local service = {
  name = "service-invalid",
  protocol = "http",
}

local headers_mt = {
  __index = function(t, k)
    local u = rawget(t, string.upper(k))
    if u then
      return u
    end

    return rawget(t, string.lower(k))
  end
}

for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
  describe("Router (flavor = " .. flavor .. ")", function()
    reload_router(flavor)
    local it_trad_only = (flavor == "traditional") and it or pending

    describe("split_port()", function()
      it("splits port number", function()
        for _, case in ipairs({
          { { "" }, { "", "", false } },
          { { "localhost" }, { "localhost", "localhost", false } },
          { { "localhost:" }, { "localhost", "localhost", false } },
          { { "localhost:80" }, { "localhost", "localhost:80", true } },
          { { "localhost:23h" }, { "localhost:23h", "localhost:23h", false } },
          { { "localhost/24" }, { "localhost/24", "localhost/24", false } },
          { { "::1" }, { "::1", "::1", false } },
          { { "[::1]" }, { "::1", "[::1]", false } },
          { { "[::1]:" }, { "::1", "[::1]:", false } },
          { { "[::1]:80" }, { "::1", "[::1]:80", true } },
          { { "[::1]:80b" }, { "[::1]:80b", "[::1]:80b", false } },
          { { "[::1]/96" }, { "[::1]/96", "[::1]/96", false } },

          { { "", 88 }, { "", ":88", false } },
          { { "localhost", 88 }, { "localhost", "localhost:88", false } },
          { { "localhost:", 88 }, { "localhost", "localhost:88", false } },
          { { "localhost:80", 88 }, { "localhost", "localhost:80", true } },
          { { "localhost:23h", 88 }, { "localhost:23h", "[localhost:23h]:88", false } },
          { { "localhost/24", 88 }, { "localhost/24", "localhost/24:88", false } },
          { { "::1", 88 }, { "::1", "[::1]:88", false } },
          { { "[::1]", 88 }, { "::1", "[::1]:88", false } },
          { { "[::1]:", 88 }, { "::1", "[::1]:88", false } },
          { { "[::1]:80", 88 }, { "::1", "[::1]:80", true } },
          { { "[::1]:80b", 88 }, { "[::1]:80b", "[::1]:80b:88", false } },
          { { "[::1]/96", 88 }, { "[::1]/96", "[::1]/96:88", false } },
        }) do
          assert.same(case[2], { Router.split_port(unpack(case[1])) })
        end
      end)
    end)

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
      local use_case, router

      lazy_setup(function()
        use_case = {

          -- 1. host
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              hosts = {
                "domain-1.org",
                "domain-2.org"
              },
            },
          },
          -- 2. method
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              methods = {
                "TRACE"
              },
            }
          },
          -- 3. uri
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
              paths = {
                "/my-route"
              },
            }
          },
          -- 4. host + uri
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8104",
              paths = {
                "/route-4"
              },
              hosts = {
                "domain-1.org",
                "domain-2.org"
              },
            },
          },
          -- 5. host + method
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8105",
              hosts = {
                "domain-1.org",
                "domain-2.org"
              },
              methods = {
                "POST",
                "PUT",
                "PATCH"
              },
            },
          },
          -- 6. uri + method
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8106",
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
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8107",
              hosts = {
                "domain-with-uri-1.org",
                "domain-with-uri-2.org"
              },
              methods = {
                "POST",
                "PUT",
                "PATCH",
              },
              paths   = {
                "/my-route-uri"
              },
            },
          },
          -- 8. serviceless-route
          {
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8108",
              paths = {
                "/serviceless"
              },
            }
          },
          -- 9. headers (single)
          {
            service = service,
            route = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8109",
              headers = {
                location = {
                  "my-location-1",
                  "my-location-2",
                },
              },
            },
          },
          -- 10. headers (multiple)
          {
            service = service,
            route = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8110",
              headers = {
                location = {
                  "my-location-1",
                },
                version = {
                  "v1",
                  "v2",
                },
              },
            },
          },
          -- 11. headers + uri
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8111",
              headers = {
                location = {
                  "my-location-1",
                  "my-location-2",
                },
              },
              paths = {
                "/headers-uri"
              },
            },
          },
          -- 12. host + headers + uri + method
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8112",
              hosts = {
                "domain-with-headers-1.org",
                "domain-with-headers-2.org"
              },
              headers = {
                location = {
                  "my-location-1",
                  "my-location-2",
                },
              },
              methods = {
                "POST",
                "PUT",
                "PATCH",
              },
              paths   = {
                "/headers-host-uri-method"
              },
            },
          },
          -- 13. host + port
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8113",
              hosts = {
                "domain-1.org:321",
                "domain-2.org"
              },
            },
          },
          -- 14. no "any-port" route
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8114",
              hosts = {
                "domain-3.org:321",
              },
            },
          },
          -- 15. headers (regex)
          {
            service = service,
            route = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8115",
              headers = {
                user_agent = {
                  "~*windows|linux|os\\s+x\\s*[\\d\\._]+|solaris|bsd",
                },
              },
            },
          },
        }
        router = assert(new_router(use_case))
      end)


      it("[host]", function()
        -- host
        local match_t = router:select("GET", "/", "domain-1.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[1].route.hosts[1], match_t.matches.host)
        end
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[host] ignores default port", function()
        -- host
        local match_t = router:select("GET", "/", "domain-1.org:80")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[1].route.hosts[1], match_t.matches.host)
        end
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it_trad_only("[host] weird port matches no-port route", function()
        local match_t = router:select("GET", "/", "domain-1.org:123")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        assert.same(use_case[1].route.hosts[1], match_t.matches.host)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[host] matches specific port", function()
        -- host
        local match_t = router:select("GET", "/", "domain-1.org:321")
        assert.truthy(match_t)
        assert.same(use_case[13].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[13].route.hosts[1], match_t.matches.host)
        end
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[host] matches specific port on port-only route", function()
        -- host
        local match_t = router:select("GET", "/", "domain-3.org:321")
        assert.truthy(match_t)
        assert.same(use_case[14].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[14].route.hosts[1], match_t.matches.host)
        end
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[host] fails just because of port on port-only route", function()
        -- host
        local match_t = router:select("GET", "/", "domain-3.org:123")
        assert.falsy(match_t)
      end)

      it("[uri]", function()
        -- uri
        local match_t = router:select("GET", "/my-route", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[3].route, match_t.route)
        assert.same(nil, match_t.matches.host)
        assert.same(nil, match_t.matches.method)
        if flavor == "traditional" then
          assert.same(use_case[3].route.paths[1], match_t.matches.uri)
        end
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[uri + empty host]", function()
        -- uri only (no Host)
        -- Supported for HTTP/1.0 requests without a Host header
        local match_t = router:select("GET", "/my-route-uri", "")
        assert.truthy(match_t)
        assert.same(use_case[3].route, match_t.route)
        assert.same(nil, match_t.matches.host)
        assert.same(nil, match_t.matches.method)
        if flavor == "traditional" then
          assert.same(use_case[3].route.paths[1], match_t.matches.uri)
        end
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[method]", function()
        -- method
        local match_t = router:select("TRACE", "/", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
        assert.same(nil, match_t.matches.host)
        if flavor == "traditional" then
          assert.same(use_case[2].route.methods[1], match_t.matches.method)
        end
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[host + uri]", function()
        -- host + uri
        local match_t = router:select("GET", "/route-4", "domain-1.org")
        assert.truthy(match_t)
        assert.same(use_case[4].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[4].route.hosts[1], match_t.matches.host)
        end
        assert.same(nil, match_t.matches.method)
        if flavor == "traditional" then
          assert.same(use_case[4].route.paths[1], match_t.matches.uri)
        end
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[host + method]", function()
        -- host + method
        local match_t = router:select("POST", "/", "domain-1.org")
        assert.truthy(match_t)
        assert.same(use_case[5].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[5].route.hosts[1], match_t.matches.host)
          assert.same(use_case[5].route.methods[1], match_t.matches.method)
        end
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[uri + method]", function()
        -- uri + method
        local match_t = router:select("PUT", "/route-6", "domain.org")
        assert.truthy(match_t)
        assert.same(use_case[6].route, match_t.route)
        assert.same(nil, match_t.matches.host)
        if flavor == "traditional" then
          assert.same(use_case[6].route.methods[2], match_t.matches.method)
          assert.same(use_case[6].route.paths[1], match_t.matches.uri)
        end
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("[host + uri + method]", function()
        -- uri + method
        local match_t = router:select("PUT", "/my-route-uri",
                                      "domain-with-uri-2.org")
        assert.truthy(match_t)
        assert.same(use_case[7].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[7].route.hosts[2], match_t.matches.host)
          assert.same(use_case[7].route.methods[2], match_t.matches.method)
          assert.same(use_case[7].route.paths[1], match_t.matches.uri)
        end
        assert.same(nil, match_t.matches.uri_captures)
      end)

      it("single [headers] value", function()
        -- headers (single)
        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = "my-location-1"
        })
        assert.truthy(match_t)
        assert.same(use_case[9].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ location = "my-location-1" }, match_t.matches.headers)
        end

        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = "my-location-2"
        })
        assert.truthy(match_t)
        assert.same(use_case[9].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ location = "my-location-2" }, match_t.matches.headers)
        end

        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = { "my-location-3", "my-location-2" }
        })
        assert.truthy(match_t)
        assert.same(use_case[9].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ location = "my-location-2" }, match_t.matches.headers)
        end

        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = "my-location-3"
        })
        assert.is_nil(match_t)

        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = { "my-location-3", "foo" }
        })
        assert.is_nil(match_t)

        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          user_agent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.116 Safari/537.36"
        })
        assert.truthy(match_t)
        assert.same(use_case[15].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ user_agent = "mozilla/5.0 (x11; linux x86_64) applewebkit/537.36 (khtml, like gecko) chrome/83.0.4103.116 safari/537.36" }, match_t.matches.headers)
        end
      end)

      it("multiple [headers] values", function()
        -- headers (multiple)
        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = "my-location-1",
          version = "v1",
        })
        assert.truthy(match_t)
        assert.same(use_case[10].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ location = "my-location-1", version = "v1", },
                        match_t.matches.headers)
        end

        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = "my-location-1",
          version = "v2",
        })
        assert.truthy(match_t)
        assert.same(use_case[10].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ location = "my-location-1", version = "v2", },
                        match_t.matches.headers)
        end

        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = { "my-location-3", "my-location-1" },
          version = "v2",
        })
        assert.truthy(match_t)
        assert.same(use_case[10].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ location = "my-location-1", version = "v2", },
                        match_t.matches.headers)
        end

        local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil, {
          location = { "my-location-3", "my-location-2" },
          version = "v2",
        })
        -- fallback to Route 9
        assert.truthy(match_t)
        assert.same(use_case[9].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        assert.same(nil, match_t.matches.uri)
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ location = "my-location-2" }, match_t.matches.headers)
        end
      end)

      it("[headers + uri]", function()
        -- headers + uri
        local match_t = router:select("GET", "/headers-uri", nil, "http", nil, nil, nil,
                                      nil, nil, { location = "my-location-2" })
        assert.truthy(match_t)
        assert.same(use_case[11].route, match_t.route)
        assert.same(nil, match_t.matches.method)
        if flavor == "traditional" then
          assert.same(use_case[11].route.paths[1], match_t.matches.uri)
        end
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same({ location = "my-location-2" }, match_t.matches.headers)
        end
      end)

      it("[host + headers + uri + method]", function()
        -- host + headers + uri + method
        local match_t = router:select("PUT", "/headers-host-uri-method",
                                      "domain-with-headers-1.org", "http",
                                      nil, nil, nil, nil, nil, {
                                        location = "my-location-2",
                                      })
        assert.truthy(match_t)
        assert.same(use_case[12].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[12].route.hosts[1], match_t.matches.host)
          assert.same(use_case[12].route.methods[2], match_t.matches.method)
          assert.same(use_case[12].route.paths[1], match_t.matches.uri)
        end
        assert.same(nil, match_t.matches.uri_captures)
        if flavor == "traditional" then
          assert.same(use_case[12].route.headers.location[2],
                      match_t.matches.headers.location)
        end
      end)

      it("[serviceless]", function()
        local match_t = router:select("GET", "/serviceless")
        assert.truthy(match_t)
        assert.is_nil(match_t.service)
        assert.is_nil(match_t.matches.uri_captures)
        assert.same(use_case[8].route, match_t.route)
        if flavor == "traditional" then
          assert.same(use_case[8].route.paths[1], match_t.matches.uri)
        end
      end)

      if flavor == "traditional" then
        describe("[IPv6 literal host]", function()
          local use_case, router

          lazy_setup(function()
            use_case = {
              -- 1: no port, with and without brackets, unique IPs
              {
                service = service,
                route = {
                  hosts = { "::11", "[::12]" },
                },
              },

              -- 2: no port, with and without brackets, same hosts as 4
              {
                service = service,
                route = {
                  hosts = { "::21", "[::22]" },
                },
              },

              -- 3: unique IPs, with port
              {
                service = service,
                route = {
                  hosts = { "[::31]:321", "[::32]:321" },
                },
              },

              -- 4: same hosts as 2, with port, needs brackets
              {
                service = service,
                route = {
                  hosts = { "[::21]:321", "[::22]:321" },
                },
              },
            }
            router = assert(new_router(use_case))
          end)

          describe("no-port route is any-port", function()
            describe("no-port request", function()
              it("plain match", function()
                local match_t = assert(router:select("GET", "/", "::11"))
                assert.same(use_case[1].route, match_t.route)
              end)
              it("with brackets", function()
                local match_t = assert(router:select("GET", "/", "[::11]"))
                assert.same(use_case[1].route, match_t.route)
              end)
            end)

            it("explicit port still matches", function()
              local match_t = assert(router:select("GET", "/", "[::11]:654"))
              assert.same(use_case[1].route, match_t.route)
            end)
          end)

          describe("port-specific route", function()
            it("matches by port", function()
              local match_t = assert(router:select("GET", "/", "[::21]:321"))
              assert.same(use_case[4].route, match_t.route)

              local match_t = assert(router:select("GET", "/", "[::31]:321"))
              assert.same(use_case[3].route, match_t.route)
            end)

            it("matches other ports to any-port fallback", function()
              local match_t = assert(router:select("GET", "/", "[::21]:654"))
              assert.same(use_case[2].route, match_t.route)
            end)

            it("fails if there's no any-port route", function()
              local match_t = router:select("GET", "/", "[::31]:654")
              assert.falsy(match_t)
            end)
          end)
        end)
      end

      describe("[uri prefix]", function()
        it("matches when given [uri] is in request URI prefix", function()
          -- uri prefix
          local match_t = router:select("GET", "/my-route/some/path", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[3].route, match_t.route)
          assert.same(nil, match_t.matches.host)
          assert.same(nil, match_t.matches.method)
          if flavor == "traditional" then
            assert.same(use_case[3].route.paths[1], match_t.matches.uri)
          end
          assert.same(nil, match_t.matches.uri_captures)
        end)

        it("does not supersede another route with a longer [uri]", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { "/my-route/hello" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                paths = { "/my-route" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/my-route/hello", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          if flavor == "traditional" then
            assert.same("/my-route/hello", match_t.matches.uri)
          end

          match_t = router:select("GET", "/my-route/hello/world", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          if flavor == "traditional" then
            assert.same("/my-route/hello", match_t.matches.uri)
          end

          match_t = router:select("GET", "/my-route", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same("/my-route", match_t.matches.uri)
          end

          match_t = router:select("GET", "/my-route/world", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same("/my-route", match_t.matches.uri)
          end
        end)

        it("does not supersede another route with a longer [uri] while [methods] are also defined", function()
          local use_case = {
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                methods = { "POST", "PUT", "GET" },
                paths   = { "/my-route" },
              },
            },
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                methods = { "POST", "PUT", "GET" },
                paths   = { "/my-route/hello" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/my-route/hello", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)

          match_t = router:select("GET", "/my-route/hello/world", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)

          match_t = router:select("GET", "/my-route", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          match_t = router:select("GET", "/my-route/world", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
        end)

        it("does not superseds another route with a longer [uri] while [hosts] are also defined", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "domain.org" },
                paths = { "/my-route" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "domain.org" },
                paths = { "/my-route/hello" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/my-route/hello", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)

          match_t = router:select("GET", "/my-route/hello/world", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)

          match_t = router:select("GET", "/my-route", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          match_t = router:select("GET", "/my-route/world", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
        end)

        it("does not supersede another route with a longer [uri] when a better [uri] match exists for another [host]", function()
          local use_case = {
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts   = { "example.com" },
                paths   = { "/my-route" },
              },
            },
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts   = { "example.com" },
                paths   = { "/my-route/hello" },
              },
            },
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
                hosts   = { "example.net" },
                paths   = { "/my-route/hello/world" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/my-route/hello/world", "example.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)

          local match_t = router:select("GET", "/my-route/hello/world/and/goodnight", "example.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        it("only matches [uri prefix] as a prefix (anchored mode)", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { "/something/my-route" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts  = { "example.com" },
                paths = { "/my-route" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/something/my-route", "example.com")
          assert.truthy(match_t)
          -- would be route-2 if URI matching was not prefix-only (anchored mode)
          assert.same(use_case[1].route, match_t.route)
          if flavor == "traditional" then
            assert.same("/something/my-route", match_t.matches.uri)
          end
        end)
      end)

      describe("[uri regex]", function()
        it("matches with [uri regex]", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { [[~/users/\d+/profile]] },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/users/123/profile", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          assert.same(nil, match_t.matches.host)
          assert.same(nil, match_t.matches.method)
          if flavor == "traditional" then
            assert.same([[/users/\d+/profile]], match_t.matches.uri)
          end
          assert.same(nil, match_t.matches.uri_captures)
        end)

        it("matches the right route when several ones have a [uri regex]", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { [[~/route/persons/\d{3}]] },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                paths = { [[~/route/persons/\d{3}/following]] },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
                paths = { [[~/route/persons/\d{3}/[a-z]+]] },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/route/persons/456", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
        end)

        it("matches a [uri regex] even if a [prefix uri] got a match", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { [[/route/persons]] },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                paths = { [[~/route/persons/\d+/profile]] },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/route/persons/123/profile",
                                        "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          assert.same(nil, match_t.matches.host)
          assert.same(nil, match_t.matches.method)
          if flavor == "traditional" then
            assert.same([[/route/persons/\d+/profile]], match_t.matches.uri)
          end
          assert.same(nil, match_t.matches.uri_captures)
        end)

        it("matches a [uri regex] even if a [uri] got an exact match", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { "/route/fixture" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                paths = { "~/route/(fixture)" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/route/fixture", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          assert.same(nil, match_t.matches.host)
          assert.same(nil, match_t.matches.method)
          if flavor == "traditional" then
            assert.same("/route/(fixture)", match_t.matches.uri)
          end
        end)

        it("matches a [uri regex + host] even if a [prefix uri] got a match", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "route.com" },
                paths = { "/pat" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "route.com" },
                paths = { "/path" },
                methods = { "POST" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
                hosts = { "route.com" },
                paths = { "~/(path)" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/path", "route.com")
          assert.truthy(match_t)
          assert.same(use_case[3].route, match_t.route)
          if flavor == "traditional" then
            assert.same("route.com", match_t.matches.host)
            assert.same("/(path)", match_t.matches.uri)
          end
          assert.same(nil, match_t.matches.method)
        end)

        it("matches from the beginning of the request URI [uri regex]", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { [[~/prefix/[0-9]+]] }
              },
            },
          }

          local router = assert(new_router(use_case))

          -- sanity
          local match_t = router:select("GET", "/prefix/123", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          assert.same(nil, match_t.matches.host)
          assert.same(nil, match_t.matches.method)

          match_t = router:select("GET", "/extra/prefix/123", "domain.org")
          assert.is_nil(match_t)
        end)
      end)

      describe("[wildcard host]", function()
        local use_case, router

        lazy_setup(function()
          use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "*.route.com" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "route.*" },
              },
            },
          }

          router = assert(new_router(use_case))
        end)

        it("matches leftmost wildcards", function()
          local match_t = router:select("GET", "/", "foo.route.com", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          if flavor == "traditional" then
            assert.same(use_case[1].route.hosts[1], match_t.matches.host)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri)
          assert.same(nil, match_t.matches.uri_captures)
        end)

        it("matches rightmost wildcards", function()
          local match_t = router:select("GET", "/", "route.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        it("matches any port in request", function()
          local match_t = router:select("GET", "/", "route.org:123")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)

          local match_t = router:select("GET", "/", "foo.route.com:123", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
        end)

        it("matches port-specific routes", function()
          table.insert(use_case, {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
              hosts = { "*.route.net:123" },
            },
          })
          table.insert(use_case, {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8104",
              hosts = { "route.*:123" },    -- same as [2] but port-specific
            },
          })
          router = assert(new_router(use_case))

          finally(function()
            table.remove(use_case)
            table.remove(use_case)
            router = assert(new_router(use_case))
          end)

          -- match the right port
          local match_t = router:select("GET", "/", "foo.route.net:123")
          assert.truthy(match_t)
          assert.same(use_case[3].route, match_t.route)

          -- fail different port
          assert.is_nil(router:select("GET", "/", "foo.route.net:456"))

          -- port-specific is higher priority
          local match_t = router:select("GET", "/", "route.org:123")
          assert.truthy(match_t)
          assert.same(use_case[4].route, match_t.route)
        end)

        it("prefers port-specific even for http default port", function()
          table.insert(use_case, {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
              hosts = { "route.*:80" },    -- same as [2] but port-specific
            },
          })
          router = assert(new_router(use_case))

          finally(function()
            table.remove(use_case)
            router = assert(new_router(use_case))
          end)

          -- non-port matches any
          local match_t = assert(router:select("GET", "/", "route.org:123"))
          assert.same(use_case[2].route, match_t.route)

          -- port 80 goes to port-specific route
          local match_t = assert(router:select("GET", "/", "route.org:80"))
          assert.same(use_case[3].route, match_t.route)

          -- even if it's implicit port 80
          if flavor == "traditional" then
            local match_t = assert(router:select("GET", "/", "route.org"))
            assert.same(use_case[3].route, match_t.route)
          end
        end)

        it("prefers port-specific even for https default port", function()
          table.insert(use_case, {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
              hosts = { "route.*:443" },    -- same as [2] but port-specific
            },
          })
          router = assert(new_router(use_case))

          finally(function()
            table.remove(use_case)
            router = assert(new_router(use_case))
          end)

          -- non-port matches any
          local match_t = assert(router:select("GET", "/", "route.org:123"))
          assert.same(use_case[2].route, match_t.route)

          -- port 443 goes to port-specific route
          local match_t = assert(router:select("GET", "/", "route.org:443"))
          assert.same(use_case[3].route, match_t.route)

          -- even if it's implicit port 443
          if flavor == "traditional" then
            local match_t = assert(router:select("GET", "/", "route.org", "https"))
            assert.same(use_case[3].route, match_t.route)
          end
        end)

        it("does not take precedence over a plain host", function()
          table.insert(use_case, 1, {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
              hosts = { "plain.route.com" },
            },
          })

          table.insert(use_case, {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8104",
              hosts = { "route.com" },
            },
          })

          finally(function()
            table.remove(use_case, 1)
            table.remove(use_case)
            router = assert(new_router(use_case))
          end)

          router = assert(new_router(use_case))

          local match_t = router:select("GET", "/", "route.com")
          assert.truthy(match_t)
          assert.same(use_case[4].route, match_t.route)
          if flavor == "traditional" then
            assert.same("route.com", match_t.matches.host)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri)
          assert.same(nil, match_t.matches.uri_captures)

          match_t = router:select("GET", "/", "route.org")
          assert.truthy(match_t)
          assert.same(use_case[3].route, match_t.route)
          if flavor == "traditional" then
            assert.same("route.*", match_t.matches.host)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri)
          assert.same(nil, match_t.matches.uri_captures)

          match_t = router:select("GET", "/", "plain.route.com")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          if flavor == "traditional" then
            assert.same("plain.route.com", match_t.matches.host)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri)
          assert.same(nil, match_t.matches.uri_captures)

          match_t = router:select("GET", "/", "foo.route.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same("*.route.com", match_t.matches.host)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri)
          assert.same(nil, match_t.matches.uri_captures)
        end)

        it("matches [wildcard host + path] even if a similar [plain host] exists", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "*.route.com" },
                paths = { "/path1" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "plain.route.com" },
                paths = { "/path2" },
              },
            },
          }

          router = assert(new_router(use_case))

          local match_t = router:select("GET", "/path1", "plain.route.com")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          if flavor == "traditional" then
            assert.same("*.route.com", match_t.matches.host)
            assert.same("/path1", match_t.matches.uri)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri_captures)
        end)

        it("matches [plain host + path] even if a matching [wildcard host] exists", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "*.route.com" },
                paths = { "/path1" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "plain.route.com" },
                paths = { "/path2" },
              },
            },
          }

          router = assert(new_router(use_case))

          local match_t = router:select("GET", "/path2", "plain.route.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same("plain.route.com", match_t.matches.host)
            assert.same("/path2", match_t.matches.uri)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri_captures)
        end)

        it("submatch_weight [wildcard host port] > [wildcard host] ", function()
          local use_case = {
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "route.*" },
              },
            },
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "route.*:80", "route.com.*" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/", "route.org:80")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same("route.*:80", match_t.matches.host)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri)
          assert.same(nil, match_t.matches.uri_captures)
        end)

        it("matches a [wildcard host + port] even if a [wildcard host] matched", function()
          local use_case = {
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "route.*" },
              },
            },
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "route.*:123" },
              },
            },
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
                hosts = { "route.*:80" },
              },
            },
          }

          local router = assert(new_router(use_case))

          -- explicit port
          local match_t = router:select("GET", "/", "route.org:123")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same("route.*:123", match_t.matches.host)
          end
          assert.same(nil, match_t.matches.method)
          assert.same(nil, match_t.matches.uri)
          assert.same(nil, match_t.matches.uri_captures)

          -- implicit port
          if flavor == "traditional" then
            local match_t = router:select("GET", "/", "route.org")
            assert.truthy(match_t)
            assert.same(use_case[3].route, match_t.route)
            assert.same("route.*:80", match_t.matches.host)
            assert.same(nil, match_t.matches.method)
            assert.same(nil, match_t.matches.uri)
            assert.same(nil, match_t.matches.uri_captures)
          end
        end)

        it("matches [wildcard/plain + uri + method]", function()
          finally(function()
            table.remove(use_case)
            router = assert(new_router(use_case))
          end)

          table.insert(use_case, {
            service   = service,
            route     = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              hosts   = { "*.domain.com", "example.com" },
              paths   = { "/path" },
              methods = { "GET", "TRACE" },
            },
          })

          router = assert(new_router(use_case))

          local match_t = router:select("POST", "/path", "foo.domain.com")
          assert.is_nil(match_t)

          match_t = router:select("GET", "/path", "foo.domain.com")
          assert.truthy(match_t)
          assert.same(use_case[#use_case].route, match_t.route)

          match_t = router:select("TRACE", "/path", "example.com")
          assert.truthy(match_t)
          assert.same(use_case[#use_case].route, match_t.route)

          match_t = router:select("POST", "/path", "foo.domain.com")
          assert.is_nil(match_t)
        end)
      end)

      describe("[wildcard host] + [uri regex]", function()
        it("matches", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "*.example.com" },
                paths = { [[~/users/\d+/profile]] },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "*.example.com" },
                paths = { [[/users]] },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/users/123/profile",
                                        "test.example.com")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          match_t = router:select("GET", "/users", "test.example.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)
      end)

      describe("[headers]", function()
        it("evaluates Routes with more [headers] first", function()
          local use_case = {
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                headers = {
                  version = { "v1", "v2" },
                  user_agent = { "foo", "bar" },
                },
              },
            },
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                headers = {
                  version = { "v1", "v2" },
                  user_agent = { "foo", "bar" },
                  location = { "east", "west" },
                },
              },
            }
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil,
                                        {
                                          version = "v1",
                                          user_agent = "foo",
                                          location = { "north", "west" },
                                        })
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        it("names are case-insensitive", function()
          local use_case = {
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                headers = {
                  ["USER_AGENT"] = { "foo", "bar" },
                },
              },
            },
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                headers = {
                  user_agent = { "baz" },
                },
              },
            }
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil,
                                        setmetatable({
                                          user_agent = "foo",
                                        }, headers_mt))
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          if flavor == "traditional" then
            assert.same({ user_agent = "foo" }, match_t.matches.headers)
          end

          local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil,
                                        setmetatable({
                                          ["USER_AGENT"] = "baz",
                                        }, headers_mt))
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same({ user_agent = "baz" }, match_t.matches.headers)
          end
        end)

        it("matches values in a case-insensitive way", function()
          local use_case = {
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                headers = {
                  user_agent = { "foo", "bar" },
                },
              },
            },
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                headers = {
                  user_agent = { "BAZ" },
                },
              },
            }
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil,
                                        {
                                          user_agent = "FOO",
                                        })
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)
          if flavor == "traditional" then
            assert.same({ user_agent = "foo" }, match_t.matches.headers)
          end

          local match_t = router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil,
                                        {
                                          user_agent = "baz",
                                        })
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same({ user_agent = "baz" }, match_t.matches.headers)
          end
        end)
      end)

      if flavor ~= "traditional" then
        describe("incremental rebuild", function()
          local router
          local use_case = {
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { "/foo", },
                updated_at = 100,
              },
            },
            {
              service = service,
              route = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                paths = { "/bar", },
                updated_at = 90,
              },
            }
          }

          before_each(function()
            router = assert(new_router(use_case))
          end)

          it("matches initially", function()
            local match_t = router:select("GET", "/foo")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)

            match_t = router:select("GET", "/bar")
            assert.truthy(match_t)
            assert.same(use_case[2].route, match_t.route)
          end)

          it("update/remove works", function()
            local use_case = {
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = { "/foo1", },
                  updated_at = 100,
                },
              },
            }

            local nrouter = assert(new_router(use_case, router))

            assert.equal(nrouter, router)

            local match_t = nrouter:select("GET", "/foo1")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)

            match_t = nrouter:select("GET", "/bar")
            assert.falsy(match_t)
          end)

          it("update with wrong route", function()
            local use_case = {
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = { "~/delay/(?<delay>[^\\/]+)$", },
                  updated_at = 100,
                },
              },
            }

            local ok, nrouter = pcall(new_router, use_case, router)

            assert(ok)
            assert.equal(nrouter, router)
            assert.equal(#nrouter.routes, 0)
          end)

          it("update skips routes if updated_at is unchanged", function()
            local use_case = {
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = { "/foo", },
                  updated_at = 100,
                },
              },
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = { "/baz", },
                  updated_at = 90,
                },
              }
            }

            local nrouter = assert(new_router(use_case, router))

            assert.equal(nrouter, router)

            local match_t = nrouter:select("GET", "/baz")
            assert.falsy(match_t)

            match_t = nrouter:select("GET", "/bar")
            assert.truthy(match_t)
            assert.same(use_case[2].route, match_t.route)
          end)

          it("clears match and negative cache after rebuild", function()
            local match_t = router:select("GET", "/baz")
            assert.falsy(match_t)

            match_t = router:select("GET", "/foo")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)

            local use_case = {
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = { "/foz", },
                  updated_at = 100,
                },
              },
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = { "/baz", },
                  updated_at = 100,
                },
              }
            }

            local nrouter = assert(new_router(use_case, router))

            assert.equal(nrouter, router)

            local match_t = nrouter:select("GET", "/foo")
            assert.falsy(match_t)

            match_t = nrouter:select("GET", "/baz")
            assert.truthy(match_t)
            assert.same(use_case[2].route, match_t.route)
          end)

          it("detects concurrent incremental builds", function()
            local use_cases = {
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = { "/foz", },
                  updated_at = 100,
                },
              },
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = { "/baz", },
                  updated_at = 100,
                },
              }
            }

            -- needs to be larger than YIELD_ITERATIONS
            for i = 1, 2000 do
              use_cases[i] = {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb" .. string.format("%04d", i),
                  paths = { "/" .. i, },
                  updated_at = 100,
                },
              }
            end

            local threads = {}

            -- make sure yield() actually works
            ngx.IS_CLI = false

            for i = 1, 10 do
              threads[i] = ngx.thread.spawn(function()
                return new_router(use_cases, router)
              end)
            end

            local error_detected = false

            for i = 1, 10 do
              local _, _, err = ngx.thread.wait(threads[i])
              if err == "concurrent incremental router rebuild without mutex, this is unsafe" then
                error_detected = true
                break
              end
            end

            ngx.IS_CLI = true

            assert.truthy(error_detected)
          end)

          it("generates the correct diff", function()
            local old_router = assert(new_router({
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = {
                    "/a"
                  },
                  updated_at = 100,
                },
              },
            }))

            local add_matcher = spy.on(old_router.router, "add_matcher")
            local remove_matcher = spy.on(old_router.router, "remove_matcher")

            assert(new_router({
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = {
                    "/b",
                  },
                  updated_at = 101,
                }
              },
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = {
                    "/c",
                  },
                  updated_at = 102,
                },
              },
            }, old_router))

            assert.spy(add_matcher).was_called(2)
            assert.spy(remove_matcher).was_called(1)
          end)

          it("remove the correct diff", function()
            local old_router = assert(new_router({
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = {
                    "/a"
                  },
                  updated_at = 100,
                },
              },
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = {
                    "/b",
                  },
                  updated_at = 100,
                },
              },
            }))

            local add_matcher = spy.on(old_router.router, "add_matcher")
            local remove_matcher = spy.on(old_router.router, "remove_matcher")

            assert(new_router({
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = {
                    "/a",
                  },
                  updated_at = 100,
                }
              },
            }, old_router))

            assert.spy(add_matcher).was_called(1)
            assert.spy(remove_matcher).was_called(2)
          end)

          it("update the correct diff: one route", function()
            local old_router = assert(new_router({
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = {
                    "/a"
                  },
                  updated_at = 100,
                },
              },
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = {
                    "/b",
                  },
                  updated_at = 90,
                },
              },
            }))

            local add_matcher = spy.on(old_router.router, "add_matcher")
            local remove_matcher = spy.on(old_router.router, "remove_matcher")

            assert(new_router({
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = {
                    "/aa",
                  },
                  updated_at = 101,
                }
              },
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = {
                    "/b",
                  },
                  updated_at = 90,
                },
              },
            }, old_router))

            assert.spy(add_matcher).was_called(1)
            assert.spy(remove_matcher).was_called(1)
          end)

          it("update the correct diff: two routes", function()
            local old_router = assert(new_router({
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = {
                    "/a"
                  },
                  updated_at = 100,
                },
              },
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = {
                    "/b",
                  },
                  updated_at = 90,
                },
              },
            }))

            local add_matcher = spy.on(old_router.router, "add_matcher")
            local remove_matcher = spy.on(old_router.router, "remove_matcher")

            assert(new_router({
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  paths = {
                    "/aa",
                  },
                  updated_at = 101,
                }
              },
              {
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                  paths = {
                    "/bb",
                  },
                  updated_at = 91,
                },
              },
            }, old_router))

            assert.spy(add_matcher).was_called(2)
            assert.spy(remove_matcher).was_called(2)
          end)
        end)

        describe("check empty route fields", function()
          local use_case
          local get_expression = atc_compat.get_expression

          before_each(function()
            use_case = {
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  methods = { "GET" },
                  paths = { "/foo", },
                },
              },
            }
          end)

          local empty_values = { {}, ngx.null, nil }
          for i = 1, 3 do
            local v = empty_values[i]

            it("empty methods", function()
              use_case[1].route.methods = v

              assert.equal(get_expression(use_case[1].route), [[(http.path ^= "/foo")]])
              assert(new_router(use_case))
            end)

            it("empty hosts", function()
              use_case[1].route.hosts = v

              assert.equal(get_expression(use_case[1].route), [[(http.method == "GET") && (http.path ^= "/foo")]])
              assert(new_router(use_case))
            end)

            it("empty headers", function()
              use_case[1].route.headers = v

              assert.equal(get_expression(use_case[1].route), [[(http.method == "GET") && (http.path ^= "/foo")]])
              assert(new_router(use_case))
            end)

            it("empty paths", function()
              use_case[1].route.paths = v

              assert.equal(get_expression(use_case[1].route), [[(http.method == "GET")]])
              assert(new_router(use_case))
            end)

            it("empty snis", function()
              use_case[1].route.snis = v

              assert.equal(get_expression(use_case[1].route), [[(http.method == "GET") && (http.path ^= "/foo")]])
              assert(new_router(use_case))
            end)
          end
        end)

        describe("check regex with '\\'", function()
          local use_case
          local get_expression = atc_compat.get_expression

          before_each(function()
            use_case = {
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  methods = { "GET" },
                },
              },
            }
          end)

          it("regex path has double '\\'", function()
            use_case[1].route.paths = { [[~/\\/*$]], }

            assert.equal([[(http.method == "GET") && (http.path ~ "^/\\\\/*$")]],
                         get_expression(use_case[1].route))
            assert(new_router(use_case))
          end)

          it("regex path has '\\d'", function()
            use_case[1].route.paths = { [[~/\d+]], }

            assert.equal([[(http.method == "GET") && (http.path ~ "^/\\d+")]],
                         get_expression(use_case[1].route))
            assert(new_router(use_case))
          end)
        end)
      end

      describe("normalization stopgap measurements", function()
        local use_case, router

        lazy_setup(function()
          use_case = {
            -- plain
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8100",
                paths = {
                  "/plain/a.b.c", -- /plain/a.b.c
                },
              },
            },
            -- percent encoding with unreserved char, route should not be normalized
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = {
                  "/plain/a.b%58c", -- /plain/a.bXc
                },
              },
            },
            -- regex. It is no longer normalized since 3.0
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                paths = {
                  "~/reg%65x/\\d+", -- /regex/\d+
                },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
                paths = {
                  "~/regex-meta/%5Cd\\+%2E", -- /regex-meta/\d\+.
                },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8104",
                paths = {
                  "~/regex-reserved%2Fabc", -- /regex-reserved/abc
                },
              },
            },
          }
          router = assert(new_router(use_case))
        end)

        it("matches against plain text paths", function()
          local match_t = router:select("GET", "/plain/a.b.c", "example.com")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          -- route no longer normalize user configured path
          match_t = router:select("GET", "/plain/a.bXc", "example.com")
          assert.falsy(match_t)
          match_t = router:select("GET", "/plain/a.b%58c", "example.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)

          match_t = router:select("GET", "/plain/aab.c", "example.com")
          assert.falsy(match_t)
        end)

        it("matches against regex paths", function()
          local match_t = router:select("GET", "/regex/123", "example.com")
          assert.falsy(match_t)

          match_t = router:select("GET", "/reg%65x/123", "example.com")
          assert.truthy(match_t)
          assert.same(use_case[3].route, match_t.route)

          match_t = router:select("GET", "/regex/\\d+", "example.com")
          assert.falsy(match_t)
        end)

        it("escapes meta character after percent decoding from regex paths", function()
          local match_t = router:select("GET", "/regex-meta/123a", "example.com")
          assert.falsy(match_t)

          match_t = router:select("GET", "/regex-meta/\\d+.", "example.com")
          assert.falsy(match_t)

          match_t = router:select("GET", "/regex-meta/%5Cd+%2E", "example.com")
          assert.truthy(match_t)
          assert.same(use_case[4].route, match_t.route)
        end)

        it("leave reserved characters alone in regex paths", function()
          local match_t = router:select("GET", "/regex-reserved/abc", "example.com")
          assert.falsy(match_t)

          match_t = router:select("GET", "/regex-reserved%2Fabc", "example.com")
          assert.truthy(match_t)
          assert.same(use_case[5].route, match_t.route)
        end)
      end)

      describe("edge-cases", function()
        it("[host] and [uri] have higher priority than [method]", function()
          local use_case = {
            -- 1. host
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = {
                  "domain-1.org",
                  "domain-2.org"
                },
              },
            },
            -- 2. method
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                methods = {
                  "TRACE"
                },
              }
            },
            -- 3. uri
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
                paths = {
                  "/my-route"
                },
              }
            },
            -- 4. host + uri
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8104",
                paths = {
                  "/route-4"
                },
                hosts = {
                  "domain-1.org",
                  "domain-2.org"
                },
              },
            },
            -- 5. host + method
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8105",
                hosts = {
                  "domain-1.org",
                  "domain-2.org"
                },
                methods = {
                  "POST",
                  "PUT",
                  "PATCH"
                },
              },
            },
            -- 6. uri + method
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8106",
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
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8107",
                hosts = {
                  "domain-with-uri-1.org",
                  "domain-with-uri-2.org"
                },
                methods = {
                  "POST",
                  "PUT",
                  "PATCH",
                },
                paths   = {
                  "/my-route-uri"
                },
              },
            },
          }
          local router = assert(new_router(use_case))
          local match_t = router:select("TRACE", "/", "domain-2.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          -- uri
          local match_t = router:select("TRACE", "/my-route", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[3].route, match_t.route)
        end)

        it("half [uri] and [host] match does not supersede another route", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts = { "host1.com" },
                paths = { "/v1/path" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "host2.com" },
                paths = { "/" },
              },
            },
          }

          local router = assert(new_router(use_case))
          local match_t = router:select("GET", "/v1/path", "host1.com")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          match_t = router:select("GET", "/v1/path", "host2.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        it("half [wildcard host] and [method] match does not supersede another route", function()
          local use_case = {
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                hosts   = { "host.*" },
                methods = { "GET" },
              },
            },
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts   = { "host.*" },
                methods = { "POST" },
              },
            },
          }

          local router = assert(new_router(use_case))
          local match_t = router:select("GET", "/", "host.com")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          match_t = router:select("POST", "/", "host.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        it("half [uri regex] and [method] match does not supersede another route", function()
          local use_case = {
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                methods = { "GET" },
                paths   = { [[~/users/\d+/profile]] },
              },
            },
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                methods = { "POST" },
                paths   = { [[~/users/\d*/profile]] },
              },
            },
          }

          local router = assert(new_router(use_case))
          local match_t = router:select("GET", "/users/123/profile", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          match_t = router:select("POST", "/users/123/profile", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        it("[method] does not supersede [uri prefix]", function()
          local use_case = {
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                methods = { "GET" },
              },
            },
            {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                paths   = { "/example" },
              },
            },
          }

          local router = assert(new_router(use_case))
          local match_t = router:select("GET", "/example", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)

          match_t = router:select("GET", "/example/status/200", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        it("[method] does not supersede [wildcard host]", function()
          local use_case = {
            {
              service    = service,
              route      = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                methods  = { "GET" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                hosts = { "domain.*" },
              },
            },
          }

          local router = assert(new_router(use_case))
          local match_t = router:select("GET", "/", "nothing.com")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          match_t = router:select("GET", "/", "domain.com")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        it_trad_only("does not supersede another route with a longer [uri prefix]", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths = { "/a", "/bbbbbbb" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                paths = { "/a/bb" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/a/bb/foobar", "domain.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)

        describe("root / [uri]", function()
          lazy_setup(function()
            table.insert(use_case, 1, {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb810f",
                paths = { "/" },
              }
            })
          end)

          lazy_teardown(function()
            table.remove(use_case, 1)
          end)

          it("request with [method]", function()
            local router = assert(new_router(use_case))
            local match_t = router:select("GET", "/", "domain.org")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)
          end)

          it("does not supersede another route", function()
            local router = assert(new_router(use_case))
            local match_t = router:select("GET", "/my-route", "domain.org")
            assert.truthy(match_t)
            assert.same(use_case[4].route, match_t.route)

            match_t = router:select("GET", "/my-route/hello/world", "domain.org")
            assert.truthy(match_t)
            assert.same(use_case[4].route, match_t.route)
          end)

          it("acts as a catch-all route", function()
            local router = assert(new_router(use_case))
            local match_t = router:select("GET", "/foobar/baz", "domain.org")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)
          end)
        end)

        describe("multiple routes of same category with conflicting values", function()
          -- reload router to reset combined cached matchers
          reload_router(flavor)

          local n = 6

          lazy_setup(function()
            -- all those routes are of the same category:
            -- [host + uri]
            for i = 1, n - 1 do
              table.insert(use_case, {
                service = service,
                route   = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb811" .. i,
                  hosts = { "domain.org" },
                  paths = { "/my-uri" },
                },
              })
            end

            table.insert(use_case, {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8121",
                hosts = { "domain.org" },
                paths = { "/my-target-uri" },
              },
            })
          end)

          lazy_teardown(function()
            for _ = 1, n do
              table.remove(use_case)
            end
          end)

          it("matches correct route", function()
            local router = assert(new_router(use_case))
            local match_t = router:select("GET", "/my-target-uri", "domain.org")
            assert.truthy(match_t)
            assert.same(use_case[#use_case].route, match_t.route)
          end)
        end)

        it("more [headers] has priority over longer [paths]", function()
          local use_case = {
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                headers = {
                  version = { "v1" },
                },
                paths = { "/my-route/hello" },
              },
            },
            {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
                headers = {
                  version = { "v1" },
                  location = { "us-east" },
                },
                paths = { "/my-route" },
              },
            },
          }

          local router = assert(new_router(use_case))

          local match_t = router:select("GET", "/my-route/hello", "domain.org", "http",
                                        nil, nil, nil, nil, nil, {
                                          version = "v1",
                                          location = "us-east",
                                        })
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same("/my-route", match_t.matches.uri)
            assert.same({ version = "v1", location = "us-east" },
                          match_t.matches.headers)
          end

          local match_t = router:select("GET", "/my-route/hello/world", "http",
                                        "domain.org", nil, nil, nil, nil, nil, {
                                          version = "v1",
                                          location = "us-east",
                                        })
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
          if flavor == "traditional" then
            assert.same("/my-route", match_t.matches.uri)
            assert.same({ version = "v1", location = "us-east" },
                          match_t.matches.headers)
          end
        end)
      end)

      describe("misses", function()
        it("invalid [host]", function()
          assert.is_nil(router:select("GET", "/", "domain-3.org"))
        end)

        it("invalid host in [host + uri]", function()
          assert.is_nil(router:select("GET", "/route-4", "domain-3.org"))
        end)

        it("invalid host in [host + method]", function()
          assert.is_nil(router:select("GET", "/", "domain-3.org"))
        end)

        it("invalid method in [host + uri + method]", function()
          assert.is_nil(router:select("GET", "/some-uri", "domain-with-uri-2.org"))
        end)

        it("invalid uri in [host + uri + method]", function()
          assert.is_nil(router:select("PUT", "/some-uri-foo",
                                      "domain-with-uri-2.org"))
        end)

        it("does not match when given [uri] is in URI but not in prefix", function()
          local match_t = router:select("GET", "/some-other-prefix/my-route",
                                        "domain.org")
          assert.is_nil(match_t)
        end)

        it("invalid [headers]", function()
          assert.is_nil(router:select("GET", "/", nil, "http", nil, nil, nil, nil, nil,
                                      { location = "invalid-location" }))
        end)

        it("invalid headers in [headers + uri]", function()
          assert.is_nil(router:select("GET", "/headers-uri",
                                      nil, "http", nil, nil, nil, nil, nil,
                                      { location = "invalid-location" }))
        end)

        it("invalid headers in [headers + uri + method]", function()
          assert.is_nil(router:select("PUT", "/headers-uri-method",
                                      nil, "http", nil, nil, nil, nil, nil,
                                      { location = "invalid-location" }))
        end)

        it("invalid headers in [headers + host + uri + method]", function()
          assert.is_nil(router:select("PUT", "/headers-host-uri-method",
                                      nil, "http", nil, nil, nil, nil, nil,
                                      { location = "invalid-location",
                                        host = "domain-with-headers-1.org" }))
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
                  id = "e8fb37f1-102d-461e-9c51-6608a1" .. string.format("%06d", i),
                  hosts = { "domain-" .. i .. ".org" },
                },
              }
            end

            target_domain = "domain-" .. #benchmark_use_cases .. ".org"
            router = assert(new_router(benchmark_use_cases))
          end)

          lazy_teardown(function()
            -- this avoids memory leakage
            router = nil
            benchmark_use_cases = nil
          end)

          it("takes < 1ms", function()
            local match_t = router:select("GET", "/", target_domain)
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
                  id = "e8fb37f1-102d-461e-9c51-6608a1" .. string.format("%06d", i),
                  hosts = { "domain-" .. n .. ".org" },
                  paths = { "/my-route-" .. n },
                },
              }
            end

            -- insert our target route, which has the proper method as well
            benchmark_use_cases[n] = {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a1" .. string.format("%06d", n),
                hosts   = { "domain-" .. n .. ".org" },
                methods = { "POST" },
                paths   = { "/my-route-" .. n },
              },
            }

            target_uri = "/my-route-" .. n
            target_domain = "domain-" .. n .. ".org"
            router = assert(new_router(benchmark_use_cases))
          end)

          lazy_teardown(function()
            -- this avoids memory leakage
            router = nil
            benchmark_use_cases = nil
          end)

          it("takes < 1ms", function()
            local match_t = router:select("POST", target_uri, target_domain)
            assert.truthy(match_t)
            assert.same(benchmark_use_cases[#benchmark_use_cases].route, match_t.route)
          end)
        end)

        describe("[headers]", function()
          describe("single key", function()
            local router
            local target_location
            local benchmark_use_cases = {}

            lazy_setup(function()
              local n = 10^5

              for i = 1, n do
                benchmark_use_cases[i] = {
                  service = service,
                  route   = {
                    id = "e8fb37f1-102d-461e-9c51-6608a1" .. string.format("%06d", i),
                    headers = {
                      location  = { "somewhere-" .. i },
                    },
                  },
                }
              end

              target_location =  "somewhere-" .. n
              router = assert(new_router(benchmark_use_cases))
            end)

            lazy_teardown(function()
              -- this avoids memory leakage
              router = nil
              benchmark_use_cases = nil
            end)

            it("takes < 1ms", function()
              local match_t = router:select("GET", "/",
                                            nil, "http", nil, nil, nil, nil, nil,
                                            { location = target_location })
              assert.truthy(match_t)
              assert.same(benchmark_use_cases[#benchmark_use_cases].route,
                          match_t.route)
            end)
          end)

          if flavor == "traditional" then
            describe("10^4 keys", function()
              local router
              local target_val
              local target_key
              local benchmark_use_cases = {}

              lazy_setup(function()
                local n = 10^5

                for i = 1, n do
                  benchmark_use_cases[i] = {
                    service = service,
                    route   = {
                      id = "e8fb37f1-102d-461e-9c51-6608a1" .. string.format("%06d", i),
                      headers = {
                        ["key-" .. i]  = { "somewhere" },
                      },
                    },
                  }
                end

                target_key = "key-" .. n
                target_val =  "somewhere"
                router = assert(new_router(benchmark_use_cases))
              end)

              lazy_teardown(function()
                -- this avoids memory leakage
                router = nil
                benchmark_use_cases = nil
              end)

              it("takes < 1ms", function()
                local match_t = router:select("GET", "/",
                                              nil, "http", nil, nil, nil, nil, nil,
                                              { [target_key] = target_val })
                assert.truthy(match_t)
                assert.same(benchmark_use_cases[#benchmark_use_cases].route,
                            match_t.route)
              end)
            end)
          end
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
                  id = "e8fb37f1-102d-461e-9c51-6608a6" .. string.format("%06d", i),
                  hosts = { "domain.org" },
                  paths = { "/my-route-" .. n },
                },
              }
            end

            -- this one too, but our target will be a
            -- different URI
            benchmark_use_cases[n] = {
              service = service,
              route   = {
                id = "e8fb37f1-102d-461e-9c51-6608a6ffffff",
                hosts = { "domain.org" },
                paths = { "/my-real-route" },
              },
            }

            target_uri = "/my-real-route"
            target_domain = "domain.org"
            router = assert(new_router(benchmark_use_cases))
          end)

          lazy_teardown(function()
            -- this avoids memory leakage
            router = nil
            benchmark_use_cases = nil
          end)

          it("takes < 1ms", function()
            local match_t = router:select("GET", target_uri, target_domain)
            assert.truthy(match_t)
            assert.same(benchmark_use_cases[#benchmark_use_cases].route, match_t.route)
          end)
        end)

        describe("[method + uri + host + headers]", function()
          local router
          local target_uri
          local target_domain
          local target_location
          local benchmark_use_cases = {}

          lazy_setup(function()
            local n = 10^5

            for i = 1, n - 1 do
              -- insert a lot of routes that don't match (missing methods)
              -- but have conflicting paths and hosts (domain-<n>.org)
              benchmark_use_cases[i] = {
                service = service,
                route   = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6" .. string.format("%06d", i),
                  hosts = { "domain-" .. n .. ".org" },
                  paths = { "/my-route-" .. n },
                  headers = {
                    location = { "somewhere-" .. n },
                  },
                },
              }
            end

            -- insert our target route, which has the proper method as well
            benchmark_use_cases[n] = {
              service   = service,
              route     = {
                id = "e8fb37f1-102d-461e-9c51-6608a6ffffff",
                hosts   = { "domain-" .. n .. ".org" },
                headers = {
                  location = { "somewhere-" .. n },
                },
                methods = { "POST" },
                paths   = { "/my-route-" .. n },
              },
            }

            target_uri = "/my-route-" .. n
            target_domain = "domain-" .. n .. ".org"
            target_location = "somewhere-" .. n
            router = assert(new_router(benchmark_use_cases))
          end)

          lazy_teardown(function()
            -- this avoids memory leakage
            router = nil
            benchmark_use_cases = nil
          end)

          it("takes < 1ms", function()
            local match_t = router:select("POST", target_uri, target_domain, "http",
                                          nil, nil, nil, nil, nil, {
              location = target_location,
            })
            assert.truthy(match_t)
            assert.same(benchmark_use_cases[#benchmark_use_cases].route,
                        match_t.route)
          end)
        end)
      end)

      describe("[errors]", function()
        it("enforces args types", function()
          assert.error_matches(function()
            router:select(1)
          end, "method must be a string", nil, true)

          assert.error_matches(function()
            router:select("GET", 1)
          end, "uri must be a string", nil, true)

          assert.error_matches(function()
            router:select("GET", "/", 1)
          end, "host must be a string", nil, true)

          assert.error_matches(function()
            router:select("GET", "/", "", 1)
          end, "scheme must be a string", nil, true)

          if flavor == "traditional" then
            assert.error_matches(function()
              router:select("GET", "/", "", "http", 1)
            end, "src_ip must be a string", nil, true)

            assert.error_matches(function()
              router:select("GET", "/", "", "http", nil, "")
            end, "src_port must be a number", nil, true)

            assert.error_matches(function()
              router:select("GET", "/", "", "http", nil, nil, 1)
            end, "dst_ip must be a string", nil, true)

            assert.error_matches(function()
              router:select("GET", "/", "", "http", nil, nil, nil, "")
            end, "dst_port must be a number", nil, true)
          end

          assert.error_matches(function()
            router:select("GET", "/", "", "http", nil, nil, nil, nil, 1)
          end, "sni must be a string", nil, true)

          assert.error_matches(function()
            router:select("GET", "/", "", "http", nil, nil, nil, nil, nil, 1)
          end, "headers must be a table", nil, true)
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
          log = ngx.log,
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
              return setmetatable(headers, headers_mt)
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
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
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
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              paths    = { "/my-route-2" },
            },
          },
        }

        local router = assert(new_router(use_case_routes))
        local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
        local get_headers = spy.on(_ngx.req, "get_headers")
        router._set_ngx(_ngx)
        local match_t = router:exec()
        assert.spy(get_headers).was_not_called()
        assert.same(use_case_routes[1].route, match_t.route)

        -- upstream_url_t
        if flavor == "traditional" then
          assert.equal("http", match_t.upstream_url_t.scheme)
        end
        assert.equal("example.org", match_t.upstream_url_t.host)
        assert.equal(80, match_t.upstream_url_t.port)

        -- upstream_uri
        assert.is_nil(match_t.upstream_host) -- only when `preserve_host = true`
        assert.equal("/my-route", match_t.upstream_uri)

        _ngx = mock_ngx("GET", "/my-route-2", { host = "domain.org" })
        get_headers = spy.on(_ngx.req, "get_headers")
        router._set_ngx(_ngx)
        match_t = router:exec()
        assert.spy(get_headers).was_not_called()
        assert.same(use_case_routes[2].route, match_t.route)

        -- upstream_url_t
        if flavor == "traditional" then
          assert.equal("https", match_t.upstream_url_t.scheme)
        end
        assert.equal("example.org", match_t.upstream_url_t.host)
        assert.equal(443, match_t.upstream_url_t.port)

        -- upstream_uri
        assert.is_nil(match_t.upstream_host) -- only when `preserve_host = true`
        assert.equal("/my-route-2", match_t.upstream_uri)
      end)

      it("returns matched_host + matched_uri + matched_method + matched_headers", function()
        local use_case_routes = {
          {
            service   = service,
            route     = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              hosts   = { "host.com" },
              methods = { "GET" },
              paths   = { "/my-route" },
            },
          },
          {
            service   = service,
            route     = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              hosts   = { "host.com" },
              paths   = { "/my-route" },
            },
          },
          {
            service   = service,
            route     = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
              hosts   = { "*.host.com" },
              headers = {
                location = { "my-location-1", "my-location-2" },
              },
            },
          },
          {
            service   = service,
            route     = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8104",
              paths   = { [[~/users/\d+/profile]] },
            },
          },
        }

        local router = assert(new_router(use_case_routes))
        local _ngx = mock_ngx("GET", "/my-route", { host = "host.com" })
        local get_headers = spy.on(_ngx.req, "get_headers")
        router._set_ngx(_ngx)
        local match_t = router:exec()
        assert.spy(get_headers).was_called(1)
        assert.same(use_case_routes[1].route, match_t.route)
        if flavor == "traditional" then
          assert.equal("host.com", match_t.matches.host)
          assert.equal("/my-route", match_t.matches.uri)
          assert.equal("GET", match_t.matches.method)
        end
        assert.is_nil(match_t.matches.headers)

        _ngx = mock_ngx("GET", "/my-route/prefix/match", { host = "host.com" })
        get_headers = spy.on(_ngx.req, "get_headers")
        router._set_ngx(_ngx)
        match_t = router:exec()
        assert.spy(get_headers).was_called(1)
        assert.same(use_case_routes[1].route, match_t.route)
        if flavor == "traditional" then
          assert.equal("host.com", match_t.matches.host)
          assert.equal("/my-route", match_t.matches.uri)
          assert.equal("GET", match_t.matches.method)
        end
        assert.is_nil(match_t.matches.headers)

        _ngx = mock_ngx("POST", "/my-route", { host = "host.com" })
        get_headers = spy.on(_ngx.req, "get_headers")
        router._set_ngx(_ngx)
        match_t = router:exec()
        assert.spy(get_headers).was_called(1)
        assert.same(use_case_routes[2].route, match_t.route)
        if flavor == "traditional" then
          assert.equal("host.com", match_t.matches.host)
          assert.equal("/my-route", match_t.matches.uri)
        end
        assert.is_nil(match_t.matches.method)
        assert.is_nil(match_t.matches.headers)

        _ngx = mock_ngx("GET", "/", {
          host = "test.host.com",
          location = "my-location-1"
        })
        get_headers = spy.on(_ngx.req, "get_headers")
        router._set_ngx(_ngx)
        match_t = router:exec()
        assert.spy(get_headers).was_called(1)
        assert.same(use_case_routes[3].route, match_t.route)
        if flavor == "traditional" then
          assert.equal("*.host.com", match_t.matches.host)
          assert.same({ location = "my-location-1" }, match_t.matches.headers)
        end
        assert.is_nil(match_t.matches.uri)
        assert.is_nil(match_t.matches.method)

        _ngx = mock_ngx("GET", "/users/123/profile", { host = "domain.org" })
        get_headers = spy.on(_ngx.req, "get_headers")
        router._set_ngx(_ngx)
        match_t = router:exec()
        assert.spy(get_headers).was_called(1)
        assert.same(use_case_routes[4].route, match_t.route)
        assert.is_nil(match_t.matches.host)
        if flavor == "traditional" then
          assert.equal([[/users/\d+/profile]], match_t.matches.uri)
        end
        assert.is_nil(match_t.matches.method)
        assert.is_nil(match_t.matches.headers)
      end)

      it("returns uri_captures from a [uri regex]", function()
        local use_case = {
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths = { [[~/users/(?P<user_id>\d+)/profile/?(?P<scope>[a-z]*)]] },
            },
          },
        }

        local router = assert(new_router(use_case))
        local _ngx = mock_ngx("GET", "/users/1984/profile",
                              { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router:exec()
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
        match_t = router:exec()
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
        match_t = router:exec()
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

      it("returns uri_captures normalized, fix #7913", function()
        local use_case = {
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths = { [[~/users/(?P<fullname>[a-zA-Z\s\d%]+)/profile/?(?P<scope>[a-z]*)]] },
            },
          },
        }


        local router = assert(new_router(use_case))
        local _ngx = mock_ngx("GET", "/users/%6aohn%20doe/profile", { host = "domain.org" })

        router._set_ngx(_ngx)
        local match_t = router:exec()
        assert.equal("john doe", match_t.matches.uri_captures[1])
        assert.equal("john doe", match_t.matches.uri_captures.fullname)
        assert.equal("",     match_t.matches.uri_captures[2])
        assert.equal("",     match_t.matches.uri_captures.scope)
        -- returns the full match as well
        assert.equal("/users/john doe/profile", match_t.matches.uri_captures[0])
        -- no stripped_uri capture
        assert.is_nil(match_t.matches.uri_captures.stripped_uri)
        assert.equal(2, #match_t.matches.uri_captures)

        -- again, this time from the LRU cache
        local match_t = router:exec()
        assert.equal("john doe", match_t.matches.uri_captures[1])
        assert.equal("john doe", match_t.matches.uri_captures.fullname)
        assert.equal("",     match_t.matches.uri_captures[2])
        assert.equal("",     match_t.matches.uri_captures.scope)
        -- returns the full match as well
        assert.equal("/users/john doe/profile", match_t.matches.uri_captures[0])
        -- no stripped_uri capture
        assert.is_nil(match_t.matches.uri_captures.stripped_uri)
        assert.equal(2, #match_t.matches.uri_captures)
      end)

      it("returns no uri_captures from a [uri prefix] match", function()
        local use_case = {
          {
            service      = service,
            route        = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths      = { "/hello" },
              strip_path = true,
            },
          },
        }

        local router = assert(new_router(use_case))
        local _ngx = mock_ngx("GET", "/hello/world", { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router:exec()
        assert.equal("/world", match_t.upstream_uri)
        assert.is_nil(match_t.matches.uri_captures)
      end)

      it("returns no uri_captures from a [uri regex] match without groups", function()
        local use_case = {
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths = { [[~/users/\d+/profile]] },
            },
          },
        }

        local router = assert(new_router(use_case))
        local _ngx = mock_ngx("GET", "/users/1984/profile",
                              { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router:exec()
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
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths    = { "/my-route" },
            },
          },
        }

        local router = assert(new_router(use_case_routes))
        local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router:exec()
        assert.same(use_case_routes[1].route, match_t.route)

        if flavor == "traditional" then
          assert.equal("/get", match_t.upstream_url_t.path)
        end
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
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
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
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              paths    = { "/my-route-2" },
            },
          },
        }

        local router = assert(new_router(use_case_routes))
        local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router:exec()
        assert.equal(8080, match_t.upstream_url_t.port)

        _ngx = mock_ngx("GET", "/my-route-2", { host = "domain.org" })
        router._set_ngx(_ngx)
        match_t = router:exec()
        assert.equal(8443, match_t.upstream_url_t.port)
      end)

      it("allows url encoded paths if they are reserved characters", function()
        local use_case_routes = {
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths = { "/endel%2Fst" },
            },
          },
        }

        local router = assert(new_router(use_case_routes))
        local _ngx = mock_ngx("GET", "/endel%2Fst", { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router:exec()
        assert.same(use_case_routes[1].route, match_t.route)
        assert.equal("/endel%2Fst", match_t.upstream_uri)
      end)

      describe("stripped paths #strip", function()
        local router
        local use_case_routes = {
          {
            service      = service,
            route        = {
              id         = uuid(),
              paths      = { "/my-route", "/xx-route" }, -- need to have same length for get_priority to work
              strip_path = true
            }
          },
          -- don't strip this route's matching URI
          {
            service      = service,
            route        = {
              id         = uuid(),
              methods    = { "POST" },
              paths      = { "/my-route", "/xx-route" }, -- need to have same length for get_priority to work
              strip_path = false,
            },
          },
        }

        lazy_setup(function()
          router = assert(new_router(use_case_routes))
        end)

        it("strips the specified paths from the given uri if matching", function()
          local _ngx = mock_ngx("GET", "/my-route/hello/world",
                                { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/my-route", match_t.prefix)
          assert.equal("/hello/world", match_t.upstream_uri)
        end)

        it("strips if matched URI is plain (not a prefix)", function()
          local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/my-route", match_t.prefix)
          assert.equal("/", match_t.upstream_uri)
        end)

        it("doesn't strip if 'strip_uri' is not enabled", function()
          local _ngx = mock_ngx("POST", "/my-route/hello/world",
                                { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.same(use_case_routes[2].route, match_t.route)
          assert.is_nil(match_t.prefix)
          assert.equal("/my-route/hello/world", match_t.upstream_uri)
        end)

        it("normalized client URI before matching and proxying", function()
          local _ngx = mock_ngx("POST", "/my-route/hello/world",
                                { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.same(use_case_routes[2].route, match_t.route)
          assert.is_nil(match_t.prefix)
          assert.equal("/my-route/hello/world", match_t.upstream_uri)
        end)

        it("does not strips root / URI", function()
          local use_case_routes = {
            {
              service      = service,
              route        = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths      = { "/" },
                strip_path = true,
              },
            },
          }

          local router = assert(new_router(use_case_routes))

          local _ngx = mock_ngx("POST", "/my-route/hello/world",
                                { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/", match_t.prefix)
          assert.equal("/my-route/hello/world", match_t.upstream_uri)
        end)

        it("can find an route with stripped URI several times in a row", function()
          local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/my-route", match_t.prefix)
          assert.equal("/", match_t.upstream_uri)

          _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
          router._set_ngx(_ngx)
          match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/my-route", match_t.prefix)
          assert.equal("/", match_t.upstream_uri)
        end)

        it("can proxy an route with stripped URI with different URIs in a row", function()
          local _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/my-route", match_t.prefix)
          assert.equal("/", match_t.upstream_uri)

          _ngx = mock_ngx("GET", "/xx-route", { host = "domain.org" })
          router._set_ngx(_ngx)
          match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/xx-route", match_t.prefix)
          assert.equal("/", match_t.upstream_uri)

          _ngx = mock_ngx("GET", "/my-route", { host = "domain.org" })
          router._set_ngx(_ngx)
          match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/my-route", match_t.prefix)
          assert.equal("/", match_t.upstream_uri)

          _ngx = mock_ngx("GET", "/xx-route", { host = "domain.org" })
          router._set_ngx(_ngx)
          match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/xx-route", match_t.prefix)
          assert.equal("/", match_t.upstream_uri)
        end)

        it("strips url encoded paths", function()
          local use_case_routes = {
            {
              service      = service,
              route        = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths      = { "/endel%2Fst" },
                strip_path = true,
              },
            },
          }

          local router = assert(new_router(use_case_routes))
          local _ngx = mock_ngx("GET", "/endel%2Fst", { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.same(use_case_routes[1].route, match_t.route)
          assert.equal("/endel%2Fst", match_t.prefix)
          assert.equal("/", match_t.upstream_uri)
        end)

        it("strips a [uri regex]", function()
          local use_case = {
            {
              service      = service,
              route        = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths      = { [[~/users/\d+/profile]] },
                strip_path = true,
              },
            },
          }

          local router = assert(new_router(use_case))
          local _ngx = mock_ngx("GET", "/users/123/profile/hello/world",
                                { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.equal("/users/123/profile", match_t.prefix)
          assert.equal("/hello/world", match_t.upstream_uri)
        end)

        it("strips a [uri regex] with a capture group", function()
          local use_case = {
            {
              service      = service,
              route        = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths      = { [[~/users/(\d+)/profile]] },
                strip_path = true,
              },
            },
          }

          local router = assert(new_router(use_case))
          local _ngx = mock_ngx("GET", "/users/123/profile/hello/world",
                                { host = "domain.org" })
          router._set_ngx(_ngx)
          local match_t = router:exec()
          assert.equal("/users/123/profile", match_t.prefix)
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
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              preserve_host = true,
              hosts         = { "preserve.com" },
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
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              preserve_host = false,
              hosts         = { "discard.com" },
            },
          },
        }

        lazy_setup(function()
          router = assert(new_router(use_case_routes))
        end)

        describe("when preserve_host is true", function()
          local host = "preserve.com"

          it("uses the request's Host header", function()
            local _ngx = mock_ngx("GET", "/", { host = host })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal(host, match_t.upstream_host)
          end)

          it("uses the request's Host header incl. port", function()
            local _ngx = mock_ngx("GET", "/", { host = host .. ":123" })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal(host .. ":123", match_t.upstream_host)
          end)

          it("does not change the target upstream", function()
            local _ngx = mock_ngx("GET", "/", { host = host })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal("example.org", match_t.upstream_url_t.host)
          end)

          it("uses the request's Host header when `grab_header` is disabled", function()
            local use_case_routes = {
              {
                service         = service,
                route           = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  name          = "route-1",
                  preserve_host = true,
                  paths         = { "/foo" },
                },
                upstream_url    = "http://example.org",
              },
            }

            local router = assert(new_router(use_case_routes))
            local _ngx = mock_ngx("GET", "/foo", { host = "preserve.com" })
            router._set_ngx(_ngx)
            local match_t = router:exec()
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
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  name          = "no-host",
                  paths         = { "/nohost" },
                  preserve_host = true,
                },
              },
            }

            local router = assert(new_router(use_case_routes))
            local _ngx = mock_ngx("GET", "/nohost", { host = "domain1.com" })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal("domain1.com", match_t.upstream_host)

            _ngx = mock_ngx("GET", "/nohost", { host = "domain2.com" })
            router._set_ngx(_ngx)
            match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal("domain2.com", match_t.upstream_host)
          end)
        end)

        describe("when preserve_host is false", function()
          local host = "discard.com"

          it("does not change the target upstream", function()
            local _ngx = mock_ngx("GET", "/", { host = host })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[2].route, match_t.route)
            assert.equal("example.org", match_t.upstream_url_t.host)
          end)

          it("does not set the host_header", function()
            local _ngx = mock_ngx("GET", "/", { host = host })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[2].route, match_t.route)
            assert.is_nil(match_t.upstream_host)
          end)
        end)
      end)

      describe("preserve Host header #grpc", function()
        local router
        local use_case_routes = {
          -- use the request's Host header
          {
            service         = {
              name          = "service-invalid",
              host          = "example.org",
              protocol      = "grpc"
            },
            route           = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              preserve_host = true,
              hosts         = { "preserve.com" },
            },
          },
          -- use the route's upstream_url's Host
          {
            service         = {
              name          = "service-invalid",
              host          = "example.org",
              protocol      = "grpc"
            },
            route           = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              preserve_host = false,
              hosts         = { "discard.com" },
            },
          },
        }

        lazy_setup(function()
          router = assert(new_router(use_case_routes))
        end)

        describe("when preserve_host is true", function()
          local host = "preserve.com"

          it("uses the request's Host header", function()
            local _ngx = mock_ngx("GET", "/", { host = host })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal(host, match_t.upstream_host)
            assert.equal("grpc", match_t.service.protocol)
          end)

          it("uses the request's Host header incl. port", function()
            local _ngx = mock_ngx("GET", "/", { host = host .. ":123" })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal(host .. ":123", match_t.upstream_host)
            assert.equal("grpc", match_t.service.protocol)
          end)

          it("does not change the target upstream", function()
            local _ngx = mock_ngx("GET", "/", { host = host })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal("example.org", match_t.upstream_url_t.host)
            assert.equal("grpc", match_t.service.protocol)
          end)

          it("uses the request's Host header when `grab_header` is disabled", function()
            local use_case_routes = {
              {
                service         = {
                  name = "service-invalid",
                  protocol = "grpc",
                },
                route           = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  name          = "route-1",
                  preserve_host = true,
                  paths         = { "/foo" },
                },
                upstream_url    = "http://example.org",
              },
            }

            local router = assert(new_router(use_case_routes))
            local _ngx = mock_ngx("GET", "/foo", { host = "preserve.com" })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal("preserve.com", match_t.upstream_host)
            assert.equal("grpc", match_t.service.protocol)
          end)

          it("uses the request's Host header if an route with no host was cached", function()
            -- This is a regression test for:
            -- https://github.com/Kong/kong/issues/2825
            -- Ensure cached routes (in the LRU cache) still get proxied with the
            -- correct Host header when preserve_host = true and no registered
            -- route has a `hosts` property.

            local use_case_routes = {
              {
                service         = {
                  name = "service-invalid",
                  protocol = "grpc",
                },
                route           = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  name          = "no-host",
                  paths         = { "/nohost" },
                  preserve_host = true,
                },
              },
            }

            local router = assert(new_router(use_case_routes))
            local _ngx = mock_ngx("GET", "/nohost", { host = "domain1.com" })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal("domain1.com", match_t.upstream_host)
            assert.equal("grpc", match_t.service.protocol)

            _ngx = mock_ngx("GET", "/nohost", { host = "domain2.com" })
            router._set_ngx(_ngx)
            match_t = router:exec()
            assert.same(use_case_routes[1].route, match_t.route)
            assert.equal("domain2.com", match_t.upstream_host)
            assert.equal("grpc", match_t.service.protocol)
          end)
        end)

        describe("when preserve_host is false", function()
          local host = "discard.com"

          it("does not change the target upstream", function()
            local _ngx = mock_ngx("GET", "/", { host = host })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[2].route, match_t.route)
            assert.equal("example.org", match_t.upstream_url_t.host)
            assert.equal("grpc", match_t.service.protocol)
          end)

          it("does not set the host_header", function()
            local _ngx = mock_ngx("GET", "/", { host = host })
            router._set_ngx(_ngx)
            local match_t = router:exec()
            assert.same(use_case_routes[2].route, match_t.route)
            assert.is_nil(match_t.upstream_host)
            assert.equal("grpc", match_t.service.protocol)
          end)
        end)
      end)

      describe("#slash handling", function()
        for i, line in ipairs(path_handling_tests) do
          for j, test in ipairs(line:expand()) do
            if flavor == "traditional" or test.path_handling == "v0" then
              local strip = test.strip_path and "on" or "off"
              local route_uri_or_host
              if test.route_path then
                route_uri_or_host = "uri " .. test.route_path
              else
                route_uri_or_host = "host localbin-" .. i .. "-" .. j .. ".com"
              end

              local description = string.format("(%d-%d) plain, %s with %s, strip = %s, %s. req: %s",
                i, j, test.service_path, route_uri_or_host, strip, test.path_handling, test.request_path)

              it(description, function()
                local use_case_routes = {
                  {
                    service      = {
                      protocol   = "http",
                      name       = "service-invalid",
                      path       = test.service_path,
                    },
                    route        = {
                      id = "e8fb37f1-102d-461e-9c51-6608a6" .. string.format("%03d%03d", i, j),
                      strip_path = test.strip_path,
                      path_handling = test.path_handling,
                      -- only add the header is no path is provided
                      hosts      = test.service_path == nil and nil or { "localbin-" .. i .. "-" .. j .. ".com" },
                      paths      = { test.route_path },
                    },
                  }
                }

                local router = assert(new_router(use_case_routes) )
                local _ngx = mock_ngx("GET", test.request_path, { host = "localbin-" .. i .. "-" .. j .. ".com" })
                router._set_ngx(_ngx)
                local match_t = router:exec()
                assert.same(use_case_routes[1].route, match_t.route)
                if flavor == "traditional" then
                  assert.same(test.service_path, match_t.upstream_url_t.path)
                end
                assert.same(test.expected_path, match_t.upstream_uri)
              end)
            end
          end
        end

        -- this is identical to the tests above, except that for the path we match
        -- with an injected regex sequence, effectively transforming the path
        -- match into a regex match
        for i, line in ipairs(path_handling_tests) do
          if line.route_path then -- skip test cases which match on host
            for j, test in ipairs(line:expand()) do
              if flavor == "traditional" or test.path_handling == "v0" then
                local strip = test.strip_path and "on" or "off"
                local regex = "~/[0]?" .. test.route_path:sub(2, -1)
                local description = string.format("(%d-%d) regex, %s with %s, strip = %s, %s. req: %s",
                  i, j, test.service_path, regex, strip, test.path_handling, test.request_path)

                it(description, function()
                  local use_case_routes = {
                    {
                      service      = {
                        protocol   = "http",
                        name       = "service-invalid",
                        path       = test.service_path,
                      },
                      route        = {
                        id = "e8fb37f1-102d-461e-9c51-6608a6" .. string.format("%03d%03d", i, j),
                        strip_path = test.strip_path,
                        -- only add the header is no path is provided
                        path_handling = test.path_handling,
                        hosts      = { "localbin-" .. i .. ".com" },
                        paths      = { regex },
                      },
                    }
                  }

                  local router = assert(new_router(use_case_routes) )
                  local _ngx = mock_ngx("GET", test.request_path, { host = "localbin-" .. i .. ".com" })
                  router._set_ngx(_ngx)
                  local match_t = router:exec()
                  assert.same(use_case_routes[1].route, match_t.route)
                  if flavor == "traditional" then
                    assert.same(test.service_path, match_t.upstream_url_t.path)
                  end
                  assert.same(test.expected_path, match_t.upstream_uri)
                end)
              end
            end
          end
        end
      end)

      it("works with special characters('\"','\\')", function()
        local use_case_routes = {
          {
            service    = {
              name     = "service-invalid",
              host     = "example.org",
              protocol = "http"
            },
            route      = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths    = { [[/\d]] },
            },
          },
          {
            service    = {
              name     = "service-invalid",
              host     = "example.org",
              protocol = "https"
            },
            route      = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              paths    = { [[~/\d+"]] },
            },
          },
        }

        local router = assert(new_router(use_case_routes))
        local _ngx = mock_ngx("GET", [[/\d]], { host = "domain.org" })
        router._set_ngx(_ngx)
        local match_t = router:exec()
        assert.same(use_case_routes[1].route, match_t.route)

        -- upstream_url_t
        if flavor == "traditional" then
          assert.equal("http", match_t.upstream_url_t.scheme)
        end
        assert.equal("example.org", match_t.upstream_url_t.host)
        assert.equal(80, match_t.upstream_url_t.port)

        -- upstream_uri
        assert.is_nil(match_t.upstream_host) -- only when `preserve_host = true`
        assert.equal([[/\d]], match_t.upstream_uri)

        _ngx = mock_ngx("GET", [[/123"]], { host = "domain.org" })
        router._set_ngx(_ngx)
        match_t = router:exec()
        assert.same(use_case_routes[2].route, match_t.route)

        -- upstream_url_t
        if flavor == "traditional" then
          assert.equal("https", match_t.upstream_url_t.scheme)
        end
        assert.equal("example.org", match_t.upstream_url_t.host)
        assert.equal(443, match_t.upstream_url_t.port)

        -- upstream_uri
        assert.is_nil(match_t.upstream_host) -- only when `preserve_host = true`
        assert.equal([[/123"]], match_t.upstream_uri)
      end)

      if flavor == "traditional_compatible" or flavor == "expressions" then
        it("gracefully handles invalid utf-8 sequences", function()
          local use_case_routes = {
            {
              service    = {
                name     = "service-invalid",
                host     = "example.org",
                protocol = "http"
              },
              route      = {
                id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                paths    = { [[/hello]] },
              },
            },
          }

          local router = assert(new_router(use_case_routes))
          local _ngx = mock_ngx("GET", "\xfc\x80\x80\x80\x80\xaf", { host = "example.org" })
          local log_spy = spy.on(_ngx, "log")

          router._set_ngx(_ngx)

          local match_t = router:exec()
          assert.is_nil(match_t)

          assert.spy(log_spy).was.called_with(ngx.ERR, "router returned an error: ",
                                              "invalid utf-8 sequence of 1 bytes from index 0",
                                              ", 404 Not Found will be returned for the current request")
        end)
      end
    end)


    if flavor == "traditional" or flavor == "traditional_compatible" then
      describe("#stream context", function()
        -- enable compat_stream
        reload_router(flavor, "stream")

        describe("[sources]", function()
          local use_case, router

          lazy_setup(function()
            use_case = {
              -- plain
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  sources = {
                    { ip = "127.0.0.1" },
                    { ip = "127.0.0.2" },
                  }
                }
              },
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
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
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
                  sources = {
                    --{ ip = "127.168.0.0/8" }, -- XXX
                    { ip = "127.0.0.0/8" },
                  }
                }
              },
              -- ip + port
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8104",
                  sources = {
                    { ip = "127.0.0.1", port = 65001 },
                  }
                }
              },
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8105",
                  sources = {
                    { ip = "127.0.0.2", port = 65300 },
                    { ip = "127.168.0.0/16", port = 65301 },
                  }
                }
              },
            }

            router = assert(new_router(use_case))
          end)

          it("[src_ip]", function()
            local match_t = router:select(nil, nil, nil, "tcp", "127.0.0.1")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)

            match_t = router:select(nil, nil, nil, "tcp", "127.0.0.1")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)
          end)

          it("[src_port]", function()
            local match_t = router:select(nil, nil, nil, "tcp", "127.0.0.3", 65001)
            assert.truthy(match_t)
            assert.same(use_case[2].route, match_t.route)
          end)

          it("[src_ip] range match", function()
            local match_t = router:select(nil, nil, nil, "tcp", "127.168.0.1")
            assert.truthy(match_t)
            assert.same(use_case[3].route, match_t.route)
          end)

          it("[src_ip] + [src_port]", function()
            local match_t = router:select(nil, nil, nil, "tcp", "127.0.0.1", 65001)
            assert.truthy(match_t)
            assert.same(use_case[4].route, match_t.route)
          end)

          it("[src_ip] range match + [src_port]", function()
            local match_t = router:select(nil, nil, nil, "tcp", "127.168.10.1", 65301)
            assert.truthy(match_t)
            assert.same(use_case[5].route, match_t.route)
          end)

          it("[src_ip] no match", function()
            local match_t = router:select(nil, nil, nil, "tcp", "10.0.0.1")
            assert.falsy(match_t)

            match_t = router:select(nil, nil, nil, "tcp", "10.0.0.2", 65301)
            assert.falsy(match_t)
          end)
        end)


        describe("[destinations]", function()
          local use_case, router

          lazy_setup(function()
            use_case = {
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

            router = assert(new_router(use_case))
          end)

          it("[dst_ip]", function()
            local match_t = router:select(nil, nil, nil, "tcp", nil, nil,
                                          "127.0.0.1")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)

            match_t = router:select(nil, nil, nil, "tcp", nil, nil,
                                    "127.0.0.1")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)
          end)

          it("[dst_port]", function()
            local match_t = router:select(nil, nil, nil, "tcp", nil, nil,
                                          "127.0.0.3", 65001)
            assert.truthy(match_t)
            assert.same(use_case[2].route, match_t.route)
          end)

          it("[dst_ip] range match", function()
            local match_t = router:select(nil, nil, nil, "tcp", nil, nil,
                                          "127.168.0.1")
            assert.truthy(match_t)
            assert.same(use_case[3].route, match_t.route)
          end)

          it("[dst_ip] + [dst_port]", function()
            local match_t = router:select(nil, nil, nil, "tcp", nil, nil,
                                          "127.0.0.1", 65001)
            assert.truthy(match_t)
            assert.same(use_case[4].route, match_t.route)
          end)

          it("[dst_ip] range match + [dst_port]", function()
            local match_t = router:select(nil, nil, nil, "tcp", nil, nil,
                                          "127.168.10.1", 65301)
            assert.truthy(match_t)
            assert.same(use_case[5].route, match_t.route)
          end)

          it("[dst_ip] no match", function()
            local match_t = router:select(nil, nil, nil, "tcp", nil, nil,
                                          "10.0.0.1")
            assert.falsy(match_t)

            match_t = router:select(nil, nil, nil, "tcp", nil, nil,
                                    "10.0.0.2", 65301)
            assert.falsy(match_t)
          end)
        end)


        describe("[snis]", function()
          local use_case, use_case_ignore_sni, router, router_ignore_sni

          lazy_setup(function()
            use_case = {
              {
                service = service,
                route = {
                  snis = { "www.example.org" }
                }
              },
              -- see #6425
              {
                service = service,
                route   = {
                  hosts = {
                    "sni.example.com",
                  },
                  protocols = {
                    "http", "https",
                  },
                  snis = {
                    "sni.example.com",
                  },
                },
              },
              {
                service = service,
                route   = {
                  hosts = {
                    "sni.example.com",
                  },
                  protocols = {
                    "http",
                  },
                },
              },
            }

            use_case_ignore_sni = {
              -- see #6425
              {
                service = service,
                route   = {
                  hosts = {
                    "sni.example.com",
                  },
                  protocols = {
                    "http", "https",
                  },
                  snis = {
                    "sni.example.com",
                  },
                },
              },
            }

            router = assert(new_router(use_case))
            router_ignore_sni = assert(new_router(use_case_ignore_sni))
          end)

          it("[sni]", function()
            local match_t = router:select(nil, nil, nil, "tcp", nil, nil, nil, nil,
                                          "www.example.org")
            assert.truthy(match_t)
            assert.same(use_case[1].route, match_t.route)
          end)

          it("[sni] is ignored for http request without shadowing routes with `protocols={'http'}`. Fixes #6425", function()
            local match_t = router_ignore_sni:select(nil, nil, "sni.example.com",
                                                     "http", nil, nil, nil, nil,
                                                     nil)
            assert.truthy(match_t)
            assert.same(use_case_ignore_sni[1].route, match_t.route)

            match_t = router:select(nil, nil, "sni.example.com",
                                    "http", nil, nil, nil, nil,
                                    nil)
            assert.truthy(match_t)
            assert.same(use_case[3].route, match_t.route)
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

          local router = assert(new_router(use_case))

          local match_t = router:select(nil, nil, nil, "tcp", "127.0.0.1", nil,
                                        nil, nil, "www.example.org")
          assert.truthy(match_t)
          assert.same(use_case[1].route, match_t.route)

          match_t = router:select(nil, nil, nil, "tcp", nil, nil,
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

          local router = assert(new_router(use_case))

          local match_t = router:select(nil, nil, nil, "tcp", "127.0.0.1", nil,
                                        "172.168.0.1", nil, "www.example.org")
          assert.truthy(match_t)
          assert.same(use_case[2].route, match_t.route)
        end)
      end)
    end

    if flavor == "traditional_compatible" then
      describe("#stream context", function()
        -- enable compat_stream
        reload_router(flavor, "stream")

        local get_expression = require("kong.router.compat").get_expression

        describe("check empty route fields", function()
          local use_case

          before_each(function()
            use_case = {
              {
                service = service,
                route = {
                  id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
                  snis = { "www.example.org" },
                  sources = {
                    { ip = "127.0.0.1" },
                  }
                },
              },
            }
          end)

          local empty_values = { {}, ngx.null, nil }
          for i = 1, 3 do
            local v = empty_values[i]

            it("empty snis", function()
              use_case[1].route.snis = v

              assert.equal(get_expression(use_case[1].route), [[(net.src.ip == 127.0.0.1)]])
              --assert(new_router(use_case))
            end)

            it("empty sources", function()
              use_case[1].route.sources = v

              assert.equal(get_expression(use_case[1].route), [[(tls.sni == "www.example.org")]])
              --assert(new_router(use_case))
            end)

            it("empty destinations", function()
              use_case[1].route.destinations = v

              assert.equal(get_expression(use_case[1].route), [[(tls.sni == "www.example.org") && (net.src.ip == 127.0.0.1)]])
              --assert(new_router(use_case))
            end)
          end
        end)
      end)  -- #stream context
    end     -- if flavor == "traditional_compatible"
  end)  -- describe("Router (flavor =
end     -- for _, flavor


describe("[both regex and prefix with regex_priority]", function()
  local use_case, router

  lazy_setup(function()
    use_case = {
      -- regex
      {
        service = service,
        route   = {
          id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
          paths = {
            "/.*"
          },
          hosts = {
            "domain-1.org",
          },
        },
      },
      -- prefix
      {
        service = service,
        route   = {
          id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
          paths = {
            "/"
          },
          hosts = {
            "domain-2.org",
          },
          regex_priority = 5
        },
      },
      {
        service = service,
        route   = {
          id = "e8fb37f1-102d-461e-9c51-6608a6bb8103",
          paths = {
            "/v1"
          },
          hosts = {
            "domain-2.org",
          },
        },
      },
    }

    router = assert(new_router(use_case))
  end)

  it("[prefix matching ignore regex_priority]", function()
    local match_t = router:select("GET", "/v1", "domain-2.org")
    assert.truthy(match_t)
    assert.same(use_case[3].route, match_t.route)
  end)

end)


for _, flavor in ipairs({ "traditional", "traditional_compatible" }) do
  describe("Router (flavor = " .. flavor .. ")", function()
    reload_router(flavor)

    describe("[both regex and prefix]", function()
      local use_case, router

      lazy_setup(function()
        use_case = {
          -- regex + prefix
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths = {
                "~/some/thing/else",
                "/foo",
              },
              hosts = {
                "domain-1.org",
              },
            },
          },
          -- prefix
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              paths = {
                "/foo/bar"
              },
              hosts = {
                "domain-1.org",
              },
            },
          },
        }

        router = assert(new_router(use_case))
      end)

      it("[assigns different priorities to regex and non-regex path]", function()
        local match_t = router:select("GET", "/some/thing/else", "domain-1.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        local match_t = router:select("GET", "/foo/bar", "domain-1.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

    end)

    describe("[overlapping prefixes]", function()
      local use_case, router

      lazy_setup(function()
        use_case = {
          -- regex + prefix
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
              paths = {
                "/foo",
                "/foo/bar/baz"
              },
              hosts = {
                "domain-1.org",
              },
            },
          },
          -- prefix
          {
            service = service,
            route   = {
              id = "e8fb37f1-102d-461e-9c51-6608a6bb8102",
              paths = {
                "/foo/bar"
              },
              hosts = {
                "domain-1.org",
              },
            },
          },
        }

        router = assert(new_router(use_case))
      end)

      it("[assigns different priorities to each path]", function()
        local match_t = router:select("GET", "/foo", "domain-1.org")
        assert.truthy(match_t)
        assert.same(use_case[1].route, match_t.route)
        local match_t = router:select("GET", "/foo/bar", "domain-1.org")
        assert.truthy(match_t)
        assert.same(use_case[2].route, match_t.route)
      end)

    end)

    it("[can create route with multiple paths and no service]", function()
      local use_case = {
        -- regex + prefix
        {
          route   = {
            id = "e8fb37f1-102d-461e-9c51-6608a6bb8101",
            paths = {
              "/foo",
              "/foo/bar/baz"
            },
          },
        }}
      assert(new_router(use_case))
    end)
  end)
end
