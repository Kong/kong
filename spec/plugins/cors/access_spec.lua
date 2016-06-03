local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local PROXY_URL = spec_helper.PROXY_URL

describe("CORS Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests-cors-1", request_host = "cors1.com", upstream_url = "http://mockbin.com" },
        { name = "tests-cors-2", request_host = "cors2.com", upstream_url = "http://mockbin.com" },
        { name = "tests-cors-3", request_host = "cors3.com", upstream_url = "http://httpbin.org" },
        { name = "tests-cors-4", request_host = "cors4.com", upstream_url = "http://httpbin.org" }
      },
      plugin = {
        { name = "cors", config = {}, __api = 1 },
        { name = "cors", config = { origin = "example.com",
                                   methods = { "GET" },
                                   headers = { "origin", "type", "accepts" },
                                   exposed_headers = { "x-auth-token" },
                                   max_age = 23,
                                   credentials = true }, __api = 2 },
        { name = "cors", config = { origin = "example.com",
                                   methods = { "GET" },
                                   headers = { "origin", "type", "accepts" },
                                   exposed_headers = { "x-auth-token" },
                                   max_age = 23,
                                   preflight_continue = true,
                                   credentials = true }, __api = 3 },
        { name = "cors", config = { origin = "example.com",
                                   methods = { "GET" },
                                   headers = { "origin", "type", "accepts" },
                                   exposed_headers = { "x-auth-token" },
                                   max_age = 23,
                                   preflight_continue = false,
                                   credentials = true }, __api = 4 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("OPTIONS", function()

    it("should give appropriate defaults when no options are passed", function()
      local _, status, headers = http_client.options(PROXY_URL.."/", {}, {host = "cors1.com"})

      -- assertions
      assert.are.equal(204, status)
      assert.are.equal("*", headers["access-control-allow-origin"])
      assert.are.equal("GET,HEAD,PUT,PATCH,POST,DELETE", headers["access-control-allow-methods"])
      assert.are.equal(nil, headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-expose-headers"])
      assert.are.equal(nil, headers["access-control-allow-credentials"])
      assert.are.equal(nil, headers["access-control-max-age"])
    end)

    it("should reflect what is specified in options", function()
      -- make proxy request
      local _, status, headers = http_client.options(PROXY_URL.."/", {}, {host = "cors2.com"})

      -- assertions
      assert.are.equal(204, status)
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("origin,type,accepts", headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-expose-headers"])
      assert.are.equal("GET", headers["access-control-allow-methods"])
      assert.are.equal(tostring(23), headers["access-control-max-age"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
    end)
    
    it("should work with preflight_continue=true and a duplicate header set by the API", function()
      -- An OPTIONS preflight request with preflight_continue=true should have the same response as directly invoking the final API
      
      local response, status, headers = http_client.options(PROXY_URL.."/headers", {}, {host = "cors3.com"})
      local response2, status2, headers2 = http_client.options("http://httpbin.org/response-headers", {}, {host = "cors3.com"})
      
      headers["via"] = nil
      headers["x-kong-proxy-latency"] = nil
      headers["x-kong-upstream-latency"] = nil
      headers["date"] = nil
      headers2["date"] = nil
      
      assert.are.equal(response, response2)
      assert.are.equal(status, status2)
      assert.are.same(headers, headers2)
      
      -- Any other request that's not a preflight request, should match our plugin configuration
      local _, status, headers = http_client.get(PROXY_URL.."/get", {}, {host = "cors3.com"})
      
      assert.are.equal(200, status)
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("x-auth-token", headers["access-control-expose-headers"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
      
      local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {["access-control-allow-origin"] = "*"}, {host = "cors3.com"})
      
      assert.are.equal(200, status)
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("x-auth-token", headers["access-control-expose-headers"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
    end)
    
    it("should work with preflight_continue=false", function()
      -- An OPTIONS preflight request with preflight_continue=false should be handled by Kong instead
      
      local response, status, headers = http_client.options(PROXY_URL.."/headers", {}, {host = "cors4.com"})
      local response2, status2, headers2 = http_client.options("http://httpbin.org/response-headers", {}, {host = "cors4.com"})
      
      headers["via"] = nil
      headers["x-kong-proxy-latency"] = nil
      headers["x-kong-upstream-latency"] = nil
      headers["date"] = nil
      headers2["date"] = nil
      
      assert.are.equal(response, response2)
      assert.are_not.equal(status, status2)
      assert.are_not.same(headers, headers2)
      
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("GET", headers["access-control-allow-methods"])
      assert.are.equal("origin,type,accepts", headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-expose-headers"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
      assert.are.equal(tostring(23), headers["access-control-max-age"])
      
      -- Any other request that's not a preflight request, should match our plugin configuration
      local _, status, headers = http_client.get(PROXY_URL.."/get", {}, {host = "cors4.com"})
      
      assert.are.equal(200, status)
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("x-auth-token", headers["access-control-expose-headers"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
    end)

    it("should work with preflight_continue=false and a duplicate header set by the API", function()
      -- An OPTIONS preflight request with preflight_continue=false should be handled by Kong instead
      
      local response, status, headers = http_client.options(PROXY_URL.."/headers", {}, {host = "cors4.com"})
      local response2, status2, headers2 = http_client.options("http://httpbin.org/response-headers", {}, {host = "cors4.com"})
      
      headers["via"] = nil
      headers["x-kong-proxy-latency"] = nil
      headers["x-kong-upstream-latency"] = nil
      headers["date"] = nil
      headers2["date"] = nil
      
      assert.are.equal(response, response2)
      assert.are_not.equal(status, status2)
      assert.are_not.same(headers, headers2)
      
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("GET", headers["access-control-allow-methods"])
      assert.are.equal("origin,type,accepts", headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-expose-headers"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
      assert.are.equal(tostring(23), headers["access-control-max-age"])
      
      -- Any other request that's not a preflight request, should match our plugin configuration
      local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {["access-control-allow-origin"] = "*"}, {host = "cors4.com"})
      
      assert.are.equal(200, status)
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("x-auth-token", headers["access-control-expose-headers"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
    end)

  end)

  describe("GET,PUT,POST,ETC", function()

    it("should give appropriate defaults when no options are passed", function()
      -- make proxy request
      local _, status, headers = http_client.get(PROXY_URL.."/", {}, {host = "cors1.com"})

      -- assertions
      assert.are.equal(200, status)
      assert.are.equal("*", headers["access-control-allow-origin"])
      assert.are.equal(nil, headers["access-control-allow-methods"])
      assert.are.equal(nil, headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-expose-headers"])
      assert.are.equal(nil, headers["access-control-allow-credentials"])
      assert.are.equal(nil, headers["access-control-max-age"])
    end)

    it("should reflect some of what is specified in options", function()
      -- make proxy request
      local _, status, headers = http_client.get(PROXY_URL.."/", {}, {host = "cors2.com"})

      -- assertions
      assert.are.equal(200, status)
      assert.are.equal("example.com", headers["access-control-allow-origin"])
      assert.are.equal("x-auth-token", headers["access-control-expose-headers"])
      assert.are.equal(nil, headers["access-control-allow-headers"])
      assert.are.equal(nil, headers["access-control-allow-methods"])
      assert.are.equal(nil, headers["access-control-max-age"])
      assert.are.equal(tostring(true), headers["access-control-allow-credentials"])
    end)

  end)

end)
