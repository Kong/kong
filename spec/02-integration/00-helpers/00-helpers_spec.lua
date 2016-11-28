local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("helpers: assertions and modifiers", function()
  local client

  setup(function()
    assert(helpers.dao:run_migrations())
    assert(helpers.dao.apis:insert {
      name = "mockbin",
      hosts = { "mockbin.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.apis:insert {
      name = "httpbin",
      hosts = { "httpbin.org" },
      upstream_url = "http://httpbin.org"
    })

    helpers.prepare_prefix()
    assert(helpers.start_kong())
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client(5000)
  end)
  after_each(function()
    if client then client:close() end
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
    it("succeeds with a mockbin response", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "mockbin.com"
        }
      })
      assert.response(r).True(true)
    end)
    it("succeeds with a httpbin response", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "httpbin.org"
        }
      })
      assert.response(r).True(true)
    end)
  end)

  describe("request modifier", function()
    it("fails with bad input", function()
      assert.error(function() assert.request().True(true) end)
      assert.error(function() assert.request(true).True(true) end)
      assert.error(function() assert.request("bad...").True(true) end)
    end)
    it("succeeds with a mockbin response", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "mockbin.com"
        }
      })
      assert.request(r).True(true)
    end)
    it("succeeds with a httpbin response", function()
      -- GET request
      local r = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "httpbin.org"
        }
      })
      assert.request(r).True(true)

      -- POST request
      local r = assert(client:send {
        method = "POST",
        path = "/post",
        body = {
          v1 = "v2"
        },
        headers = {
          host = "httpbin.org",
          ["Content-Type"] = "www-form-urlencoded"
        }
      })
      assert.request(r).True(true)
    end)
    it("fails with a non httpbin/mockbin response", function()
      local r = assert(client:send {
        method = "GET",
        path = "/headers",   -- this path is not supported, but should yield valid json for the test
        headers = {
          host = "httpbin.org"
        }
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
      local r = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "httpbin.org"
        }
      })
      assert.status(200, r)
      local body = assert.response(r).has.status(200)
      assert(cjson.decode(body))

      local r = assert(client:send {
        method = "GET",
        path = "/status/404",
        headers = {
          host = "httpbin.org"
        }
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
    it("succeeds on a response object", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "mockbin.com"
        }
      })
      local json = assert.response(r).has.jsonbody()
      assert(json.url:find("mockbin%.com"), "expected a mockbin response")
    end)
    it("succeeds on a mockbin request object", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        body = { hello = "world" },
        headers = {
          host = "mockbin.com",
          ["Content-Type"] = "application/json"
        }
      })
      local json = assert.request(r).has.jsonbody()
      assert.equals("world", json.hello)
    end)
    it("fails on a httpbin request object", function()
      local r = assert(client:send {
        method = "POST",
        path = "/post",
        body = { hello = "world" },
        headers = {
          host = "httpbin.org",
          ["Content-Type"] = "application/json"
        }
      })
      assert.error(function() assert.request(r).has.jsonbody() end)
    end)
  end)

  describe("header assertion", function()
    it("checks appropriate response headers", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        body = { hello = "world" },
        headers = {
          host = "mockbin.com",
          ["Content-Type"] = "application/json"
        }
      })
      local v1 = assert.response(r).has.header("x-powered-by")
      local v2 = assert.response(r).has.header("X-POWERED-BY")
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.header("does not exists") end)
    end)
    it("checks appropriate mockbin request headers", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "mockbin.com",
          ["just-a-test-header"] = "just-a-test-value"
        }
      })
      local v1 = assert.request(r).has.header("just-a-test-header")
      local v2 = assert.request(r).has.header("just-a-test-HEADER")
      assert.equals("just-a-test-value", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.header("does not exists") end)
    end)
    it("checks appropriate httpbin request headers", function()
      local r = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "httpbin.org",
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
    it("checks appropriate mockbin query parameters", function()
      local r = assert(client:send {
        method = "GET",
        path = "/request",
        query = {
          hello = "world"
        },
        headers = {
          host = "mockbin.com"
        }
      })
      local v1 = assert.request(r).has.queryparam("hello")
      local v2 = assert.request(r).has.queryparam("HELLO")
      assert.equals("world", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.queryparam("notHere") end)
    end)
    it("checks appropriate httpbin query parameters", function()
      local r = assert(client:send {
        method = "POST",
        path = "/post",
        query = {
          hello = "world"
        },
        body = {
          hello2 = "world2"
        },
        headers = {
          host = "httpbin.org",
          ["Content-Type"] = "application/json"
        }
      })
      local v1 = assert.request(r).has.queryparam("hello")
      local v2 = assert.request(r).has.queryparam("HELLO")
      assert.equals("world", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.queryparam("notHere") end)
    end)
  end)

  describe("formparam assertion", function()
    it("checks appropriate mockbin url-encoded form parameters", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world"
        },
        headers = {
          host = "mockbin.com",
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })
      local v1 = assert.request(r).has.formparam("hello")
      local v2 = assert.request(r).has.formparam("HELLO")
      assert.equals("world", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.request(r).has.queryparam("notHere") end)
    end)
    it("fails with mockbin non-url-encoded form data", function()
      local r = assert(client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world"
        },
        headers = {
          host = "mockbin.com",
          ["Content-Type"] = "application/json"
        }
      })
      assert.error(function() assert.request(r).has.formparam("hello") end)
    end)
    it("checks appropriate httpbin url-encoded form parameters", function()
      local r = assert(client:send {
        method = "POST",
        path = "/post",
        body = {
          hello = "world"
        },
        headers = {
          host = "httpbin.org",
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })
      local v1 = assert.request(r).has.formparam("hello")
      local v2 = assert.request(r).has.formparam("HELLO")
      assert.equals("world", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.request(r).has.queryparam("notHere") end)
    end)
    it("fails with httpbin non-url-encoded form parameters", function()
      local r = assert(client:send {
        method = "POST",
        path = "/post",
        body = {
          hello = "world"
        },
        headers = {
          host = "httpbin.org",
          ["Content-Type"] = "application/json"
        }
      })
      assert.error(function() assert.request(r).has.formparam("hello") end)
    end)
  end)
end)
