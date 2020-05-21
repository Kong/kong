local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("helpers [#" .. strategy .. "]: assertions and modifiers", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })

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

    lazy_teardown(function()
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
      it("encodes nested tables and arrays in Kong-compatible way when using form-urlencoded content-type", function()
        local tests = {
          { input = { names = { "alice", "bob", "casius" } },
            expected = { ["names[1]"] = "alice",
                         ["names[2]"] = "bob",
                         ["names[3]"] = "casius" } },

          { input = { headers = { location = { "here", "there", "everywhere" } } },
            expected = { ["headers.location[1]"] = "here",
                         ["headers.location[2]"] = "there",
                         ["headers.location[3]"] = "everywhere" } },

          { input = { ["hello world"] = "foo, bar" } ,
            expected = { ["hello world"] = "foo, bar" } },

          { input = { hash = { answer = 42 } },
            expected = { ["hash.answer"] = "42" } },

          { input = { hash_array = { arr = { "one", "two" } } },
            expected = { ["hash_array.arr[1]"] = "one",
                         ["hash_array.arr[2]"] = "two" } },

          { input = { array_hash = { { name = "peter" } } },
            expected = { ["array_hash[1].name"] = "peter" } },

          { input = { array_array = { { "x", "y" } } },
            expected = { ["array_array[1][1]"] = "x",
                         ["array_array[1][2]"] = "y" } },

          { input = { hybrid = { 1, 2, n = 3 } },
            expected = { ["hybrid[1]"] = "1",
                         ["hybrid[2]"] = "2",
                         ["hybrid.n"] = "3" } },
        }

        for i = 1, #tests do
          local r = proxy_client:get("/", {
            headers = {
              ["Content-type"] = "application/x-www-form-urlencoded",
              host             = "mock_upstream",
            },
            body = tests[i].input
          })
          local json = assert.response(r).has.jsonbody()
          assert.same(tests[i].expected, json.post_data.params)
        end
      end)
    end)

    describe("get_version()", function()
      it("gets the version of Kong running", function()
        local meta = require 'kong.meta'
        local version = require 'version'
        assert.equal(version(meta._VERSION), helpers.get_version())
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


    describe("certificates,", function()

      local function get_cert(server_name)
        local _, _, stdout = assert(helpers.execute(
          string.format("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
                        helpers.get_proxy_port(true), server_name)
        ))
        return stdout
      end


      it("cn assertion with 2 parameters, positive success", function()
        local cert = get_cert("ssl1.com")
        assert.has.cn("localhost", cert)
      end)

      it("cn assertion with 2 parameters, positive failure", function()
        local cert = get_cert("ssl1.com")
        assert.has.error(function()
          assert.has.cn("some.other.host.org", cert)
        end)
      end)

      it("cn assertion with 2 parameters, negative success", function()
        local cert = get_cert("ssl1.com")
        assert.Not.cn("some.other.host.org", cert)
      end)

      it("cn assertion with 2 parameters, negative failure", function()
        local cert = get_cert("ssl1.com")
        assert.has.error(function()
          assert.Not.cn("localhost", cert)
        end)
      end)

      it("cn assertion with modifier and 1 parameter", function()
        local cert = get_cert("ssl1.com")
        assert.certificate(cert).has.cn("localhost")
      end)

      it("cn assertion with modifier and 2 parameters fails", function()
        local cert = get_cert("ssl1.com")
        assert.has.error(function()
          assert.certificate(cert).has.cn("localhost", cert)
        end)
      end)

    end)

  end)
end
