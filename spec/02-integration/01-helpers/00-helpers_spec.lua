local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("helpers [#" .. strategy .. "]: assertions and modifiers", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local service = bp.services:insert {
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      }

      bp.routes:insert {
        hosts     = { "mock_upstream" },
        protocols = { "http" },
        service   = service
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client(5000)
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("http_client", function()
      it("encodes arrays in a way Lapis-compatible way when using form-urlencoded content-type", function()
        local r = proxy_client:get("/", {
          headers = {
            ["Content-type"] = "application/x-www-form-urlencoded",
            host             = "mock_upstream",
          },
          body    = {
            names = { "alice", "bob", "casius" },
          },
        })
        local json = assert.response(r).has.jsonbody()
        local params = json.post_data.params
        assert.equals("alice",  params["names[1]"])
        assert.equals("bob",    params["names[2]"])
        assert.equals("casius", params["names[3]"])
      end)
    end)


    describe("wait_until()", function()
      it("does not errors out if thing happens", function()
        assert.has_no_error(function()
          local i = 0
          helpers.wait_until(function()
            i = i + 1
            return i > 1
          end, 3)
        end)
      end)
      it("errors out after delay", function()
        assert.error_matches(function()
          helpers.wait_until(function()
            return false, "thing still not done"
          end, 1)
        end, "timeout: thing still not done")
      end)
      it("reports errors in test function", function()
        assert.error_matches(function()
          helpers.wait_until(function()
            assert.equal("foo", "bar")
          end, 1)
        end, "Expected objects to be equal.", nil, true)
      end)
    end)

    describe("response modifier", function()
      it("fails with bad input", function()
        assert.error(function() assert.response().True(true) end)
        assert.error(function() assert.response(true).True(true) end)
        assert.error(function() assert.response("bad...").True(true) end)
      end)
      it("succeeds with a mock_upstream response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.response(r).True(true)
      end)
      it("succeeds with a mock upstream response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/anything",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.response(r).True(true)
      end)
    end)

    describe("request modifier", function()
      it("fails with bad input", function()
        assert.error(function() assert.request().True(true) end)
        assert.error(function() assert.request(true).True(true) end)
        assert.error(function() assert.request("bad... ").True(true) end)
      end)
      it("succeeds with a mock_upstream response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.request(r).True(true)
      end)
      it("succeeds with a mock_upstream response", function()
        -- GET request
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.request(r).True(true)

        -- POST request
        local r = assert(proxy_client:send {
          method = "POST",
          path   = "/post",
          body   = {
            v1 = "v2",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "www-form-urlencoded",
          },
        })
        assert.request(r).True(true)
      end)
      it("fails with a non mock_upstream response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/headers",   -- this path is not supported, but should yield valid json for the test
          headers = {
            host = "127.0.0.1:15555",
          },
        })
        assert.error(function() assert.request(r).True(true) end)
      end)
    end)

    describe("contains assertion", function()
      it("verifies content properly", function()
        local arr = { "one", "three" }
        assert.equals(1, assert.contains("one", arr))
        assert.not_contains("two", arr)
        assert.equals(2, assert.contains("ee$", arr, true))
      end)
    end)

    describe("status assertion", function()
      it("succeeds with a response", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.status(200, r)
        local body = assert.response(r).has.status(200)
        assert(cjson.decode(body))

        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/status/404",
          headers = {
            host = "mock_upstream",
          },
        })
        assert.response(r).has.status(404)
      end)
      it("fails with bad input", function()
        assert.error(function() assert.status(200, nil) end)
        assert.error(function() assert.status(200, {}) end)
      end)
    end)

    describe("jsonbody assertion", function()
      it("fails with explicit or no parameters", function()
        assert.error(function() assert.jsonbody({}) end)
        assert.error(function() assert.jsonbody() end)
      end)
      it("succeeds on a response object on /request", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host = "mock_upstream",
          },
        })
        local json = assert.response(r).has.jsonbody()
        assert(json.url:find(helpers.mock_upstream_host), "expected a mock_upstream response")
      end)
      it("succeeds on a mock_upstream request object on /request", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = { hello = "world" },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.equals("world", json.params.hello)
      end)
      it("succeeds on a mock_upstream request object on /post", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          body    = { hello = "world" },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        local json = assert.request(r).has.jsonbody()
        assert.equals("world", json.params.hello)
      end)
    end)

    describe("header assertion", function()
      it("checks appropriate response headers", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          body    = { hello = "world" },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        local v1 = assert.response(r).has.header("x-powered-by")
        local v2 = assert.response(r).has.header("X-POWERED-BY")
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.header("does not exists") end)
      end)
      it("checks appropriate mock_upstream request headers", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host                   = "mock_upstream",
            ["just-a-test-header"] = "just-a-test-value"
          }
        })
        local v1 = assert.request(r).has.header("just-a-test-header")
        local v2 = assert.request(r).has.header("just-a-test-HEADER")
        assert.equals("just-a-test-value", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.header("does not exists") end)
      end)
      it("checks appropriate mock_upstream request headers", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host                   = "mock_upstream",
            ["just-a-test-header"] = "just-a-test-value"
          }
        })
        local v1 = assert.request(r).has.header("just-a-test-header")
        local v2 = assert.request(r).has.header("just-a-test-HEADER")
        assert.equals("just-a-test-value", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.header("does not exists") end)
      end)
    end)

    describe("queryParam assertion", function()
      it("checks appropriate mock_upstream query parameters", function()
        local r = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          query   = {
            hello = "world",
          },
          headers = {
            host = "mock_upstream",
          },
        })
        local v1 = assert.request(r).has.queryparam("hello")
        local v2 = assert.request(r).has.queryparam("HELLO")
        assert.equals("world", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.queryparam("notHere") end)
      end)
      it("checks appropriate mock_upstream query parameters", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          query   = {
            hello = "world",
          },
          body    = {
            hello2 = "world2",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        local v1 = assert.request(r).has.queryparam("hello")
        local v2 = assert.request(r).has.queryparam("HELLO")
        assert.equals("world", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.response(r).has.queryparam("notHere") end)
      end)
    end)

    describe("formparam assertion", function()
      it("checks appropriate mock_upstream url-encoded form parameters", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          },
        })
        local v1 = assert.request(r).has.formparam("hello")
        local v2 = assert.request(r).has.formparam("HELLO")
        assert.equals("world", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.request(r).has.queryparam("notHere") end)
      end)
      it("fails with mock_upstream non-url-encoded form data", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        assert.error(function() assert.request(r).has.formparam("hello") end)
      end)
      it("checks appropriate mock_upstream url-encoded form parameters", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          body    = {
            hello = "world",
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/x-www-form-urlencoded",
          },
        })
        local v1 = assert.request(r).has.formparam("hello")
        local v2 = assert.request(r).has.formparam("HELLO")
        assert.equals("world", v1)
        assert.equals(v1, v2)
        assert.error(function() assert.request(r).has.queryparam("notHere") end)
      end)
      it("fails with mock_upstream non-url-encoded form parameters", function()
        local r = assert(proxy_client:send {
          method  = "POST",
          path    = "/post",
          body    = {
            hello = "world"
          },
          headers = {
            host             = "mock_upstream",
            ["Content-Type"] = "application/json",
          },
        })
        assert.error(function() assert.request(r).has.formparam("hello") end)
      end)
    end)
  end)
end
