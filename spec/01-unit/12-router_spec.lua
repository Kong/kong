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

      it("enforces apis fields types", function()
        local router, err = Router.new {
          { name = "api-invalid" }
        }

        assert.is_nil(router)
        assert.equal("could not categorize API", err)
      end)
    end)
  end)

  describe("exec()", function()
    local router = assert(Router.new(use_case))

    it("[host]", function()
      -- host
      local api = router.exec("GET", "/", { ["host"] = "domain-1.org" })
      assert.same(use_case[1], api)
    end)

    it("[uri]", function()
      -- uri
      local api = router.exec("GET", "/my-api", {})
      assert.same(use_case[3], api)
    end)

    it("[method]", function()
      -- method
      local api = router.exec("TRACE", "/", {})
      assert.same(use_case[2], api)
    end)

    it("[host + uri]", function()
      -- host + uri
      local api = router.exec("GET", "/api-4", { ["host"] = "domain-1.org" })
      assert.same(use_case[4], api)
    end)

    it("[host + method]", function()
      -- host + method
      local api = router.exec("POST", "/", { ["host"] = "domain-1.org" })
      assert.same(use_case[5], api)
    end)

    it("[uri + method]", function()
      -- uri + method
      local api = router.exec("PUT", "/api-6", {})
      assert.same(use_case[6], api)
    end)

    it("[host + uri + method]", function()
      -- uri + method
      local api = router.exec("PUT", "/my-api-uri", { ["host"] = "domain-with-uri-2.org" })
      assert.same(use_case[7], api)
    end)

    describe("edge-cases", function()
      it("[host] and [uri] have higher priority than [method]", function()
        -- host
        local api = router.exec("TRACE", "/", { ["host"] = "domain-2.org" })
        assert.same(use_case[1], api)

        -- uri
        local api = router.exec("TRACE", "/my-api", {})
        assert.same(use_case[3], api)
      end)

      describe("root / [uri]", function()
        setup(function()
          table.insert(use_case, {
            name = "api-root-uri",
            uris = {"/"},
          })
        end)

        teardown(function()
          table.remove(use_case)
        end)

        it(function()
          local router = assert(Router.new(use_case))
          local api = router.exec("GET", "/", {})
          assert.same(use_case[#use_case], api)
        end)
      end)

      describe("multiple APIs of same category with conflicting values", function()
        -- reload router to reset combined cached matchers
        reload_router()

        local n = 6

        setup(function()
          -- all those APIs are of the same category:
          -- [host + uri]
          for i = 1, n - 1 do
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
          for i = 1, n do
            table.remove(use_case)
          end
        end)

        it(function()
          local router = assert(Router.new(use_case))
          local api = router.exec("GET", "/my-target-uri", { ["host"] = "domain.org" })
          assert.same(use_case[#use_case], api)
        end)
      end)
    end)

    describe("misses", function()
      it("invalid [host]", function()
        assert.is_nil(router.exec("GET", "/", { ["host"] = "domain-3.org" }))
      end)

      it("invalid host in [host + uri]", function()
        assert.is_nil(router.exec("GET", "/api-4", { ["host"] = "domain-3.org" }))
      end)

      it("invalid host in [host + method]", function()
        assert.is_nil(router.exec("GET", "/", { ["host"] = "domain-3.org" }))
      end)

      it("invalid method in [host + uri + method]", function()
        assert.is_nil(router.exec("GET", "/my-api-uri", { ["host"] = "domain-with-uri-2.org" }))
      end)

      it("invalid uri in [host + uri + method]", function()
        assert.is_nil(router.exec("PUT", "/my-api-uri-foo", { ["host"] = "domain-with-uri-2.org" }))
      end)
    end)

    pending("stripped uris", function()
      local router
      local use_case_apis = {
        {
          name = "api-1",
          uris = { "/my-api", "/this-api" },
          strip_uris = { "/my-api" },
        },
        -- don't strip this API's matching URI
        {
          name = "api-1",
          methods = { "POST" },
          uris = { "/my-api", "/this-api" },
        },
      }

      setup(function()
        router = assert(Router.new(use_case_apis))
      end)

      it("strips the specified uris from the given uri if matching", function()
        local api = router.exec("GET", "/my-api", {})
        assert.same(use_case_apis[1], api)

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
          local api = router.exec("GET", "/", { ["host"] = target_domain })
          assert.same(benchmark_use_cases[#benchmark_use_cases], api)
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
          local api = router.exec("POST", target_uri, { ["host"] = target_domain })
          assert.same(benchmark_use_cases[#benchmark_use_cases], api)
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
            uris = { "/my-real-api"},
            headers = {
              ["host"] = { "domain.org" },
            },
          }

          target_uri = "/my-real-api"
          target_domain = "domain.org"
          router = assert(Router.new(benchmark_use_cases))
        end)

        it("takes < 1ms", function()
          local api = router.exec("GET", target_uri, { ["host"] = target_domain })
          assert.same(benchmark_use_cases[#benchmark_use_cases], api)
        end)
      end)
    end)

    describe("[errors]", function()
      it("enforces args types", function()
        assert.error_matches(function()
          router.exec()
        end, "arg #1 method must be a string", nil, true)

        assert.error_matches(function()
          router.exec("GET")
        end, "arg #2 uri must be a string", nil, true)

        assert.error_matches(function()
          router.exec("GET", "/")
        end, "arg #3 headers must be a table", nil, true)
      end)
    end)
  end)
end)
