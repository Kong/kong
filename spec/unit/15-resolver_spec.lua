-- Stubs
require "kong.tools.ngx_stub"

local singletons = require "kong.singletons"
local resolver = require "kong.core.resolver"

local APIS_FIXTURES = {
  -- request_host
  {name = "mockbin", request_host = "mockbin.com", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_host = "mockbin-auth.com", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_host = "*.wildcard.com", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_host = "wildcard.*", upstream_url = "http://mockbin.com"},
  -- request_path
  {name = "mockbin", request_path = "/mockbin", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_path = "/mockbin-with-dashes", upstream_url = "http://mockbin.com/some/path"},
  {name = "mockbin", request_path = "/some/deep", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_path = "/some/deep/url", upstream_url = "http://mockbin.com"},
  --
  {name = "mockbin", request_path = "/strip", upstream_url = "http://mockbin.com/some/path/", strip_request_path = true},
  {name = "mockbin", request_path = "/strip-me", upstream_url = "http://mockbin.com/", strip_request_path = true},
  {name = "preserve-host", request_path = "/preserve-host", request_host = "preserve-host.com", upstream_url = "http://mockbin.com", preserve_host = true}
}

singletons.dao = {
  apis = {
    find_all = function()
      return APIS_FIXTURES
    end
  }
}

local apis_dics

describe("Resolver", function()
  describe("load_apis_in_memory()", function()
    it("should retrieve all APIs in datastore and return them organized", function()
      apis_dics = resolver.load_apis_in_memory()
      assert.equal("table", type(apis_dics))
      assert.truthy(apis_dics.by_dns)
      assert.truthy(apis_dics.request_path_arr)
      assert.truthy(apis_dics.wildcard_dns_arr)
    end)
    it("should return a dictionary of APIs by request_host", function()
      assert.equal("table", type(apis_dics.by_dns["mockbin.com"]))
      assert.equal("table", type(apis_dics.by_dns["mockbin-auth.com"]))
    end)
    it("should return an array of APIs by request_path", function()
      assert.equal("table", type(apis_dics.request_path_arr))
      assert.equal(7, #apis_dics.request_path_arr)
      for _, item in ipairs(apis_dics.request_path_arr) do
        assert.truthy(item.strip_request_path_pattern)
        assert.truthy(item.request_path)
        assert.truthy(item.api)
      end
      assert.equal("/strip%-me", apis_dics.request_path_arr[1].strip_request_path_pattern)
      assert.equal("/strip", apis_dics.request_path_arr[2].strip_request_path_pattern)
    end)
    it("should return an array of APIs with wildcard request_host", function()
      assert.equal("table", type(apis_dics.wildcard_dns_arr))
      assert.equal(2, #apis_dics.wildcard_dns_arr)
      for _, item in ipairs(apis_dics.wildcard_dns_arr) do
        assert.truthy(item.api)
        assert.truthy(item.pattern)
      end
      assert.equal("^.+%.wildcard%.com$", apis_dics.wildcard_dns_arr[1].pattern)
      assert.equal("^wildcard%..+$", apis_dics.wildcard_dns_arr[2].pattern)
    end)
  end)
  describe("strip_request_path()", function()
    it("should strip the api's request_path from the requested URI", function()
      assert.equal("/status/200", resolver.strip_request_path("/mockbin/status/200", apis_dics.request_path_arr[7].strip_request_path_pattern))
      assert.equal("/status/200", resolver.strip_request_path("/mockbin-with-dashes/status/200", apis_dics.request_path_arr[6].strip_request_path_pattern))
      assert.equal("/", resolver.strip_request_path("/mockbin", apis_dics.request_path_arr[7].strip_request_path_pattern))
      assert.equal("/", resolver.strip_request_path("/mockbin/", apis_dics.request_path_arr[7].strip_request_path_pattern))
    end)
    it("should only strip the first pattern", function()
      assert.equal("/mockbin/status/200/mockbin", resolver.strip_request_path("/mockbin/mockbin/status/200/mockbin", apis_dics.request_path_arr[7].strip_request_path_pattern))
    end)
    it("should not add final slash", function()
      assert.equal("hello", resolver.strip_request_path("hello", apis_dics.request_path_arr[3].strip_request_path_pattern, true))
      assert.equal("/hello", resolver.strip_request_path("hello", apis_dics.request_path_arr[3].strip_request_path_pattern, false))
    end)
  end)

  -- Note: ngx.var.request_uri always adds a trailing slash even with a request without any
  -- `curl kong:8000` will result in ngx.var.request_uri being '/'
  describe("execute()", function()
    local DEFAULT_REQUEST_URI = "/"

    it("should find an API by the request's simple Host header", function()
      local api, upstream_url, upstream_host = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = "mockbin.com"})
      assert.same(APIS_FIXTURES[1], api)
      assert.equal("http://mockbin.com/", upstream_url)
      assert.equal("mockbin.com", upstream_host)

      api = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = "mockbin-auth.com"})
      assert.same(APIS_FIXTURES[2], api)

      api = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = {"example.com", "mockbin.com"}})
      assert.same(APIS_FIXTURES[1], api)
    end)
    it("should find an API by the request's wildcard Host header", function()
      local api, upstream_url, upstream_host = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = "foobar.wildcard.com"})
      assert.same(APIS_FIXTURES[3], api)
      assert.equal("http://mockbin.com/", upstream_url)
      assert.equal("mockbin.com", upstream_host)

      api = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = "something.wildcard.com"})
      assert.same(APIS_FIXTURES[3], api)

      api = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = "wildcard.com"})
      assert.same(APIS_FIXTURES[4], api)

      api = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = "wildcard.fr"})
      assert.same(APIS_FIXTURES[4], api)
    end)
    it("should find an API by the request's URI (path component)", function()
      local api, upstream_url, upstream_host = resolver.execute("/mockbin", {})
      assert.same(APIS_FIXTURES[5], api)
      assert.equal("http://mockbin.com/mockbin", upstream_url)
      assert.equal("mockbin.com", upstream_host)

      api = resolver.execute("/mockbin-with-dashes", {})
      assert.same(APIS_FIXTURES[6], api)

      api = resolver.execute("/some/deep/url", {})
      assert.same(APIS_FIXTURES[8], api)

      api = resolver.execute("/mockbin-with-dashes/and/some/uri", {})
      assert.same(APIS_FIXTURES[6], api)
    end)
    it("should return a 404 HTTP response if no API was found", function()
      local responses = require "kong.tools.responses"
      spy.on(responses, "send_HTTP_NOT_FOUND")
      finally(function()
        responses.send_HTTP_NOT_FOUND:revert()
      end)

      -- non existant request_path
      local api, upstream_url, upstream_host = resolver.execute("/inexistant-mockbin", {})
      assert.falsy(api)
      assert.falsy(upstream_url)
      assert.falsy(upstream_host)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called(1)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called_with({
        message = "API not found with these values",
        request_host = {},
        request_path = "/inexistant-mockbin"
      })
      assert.equal(404, ngx.status)
      ngx.status = nil

      -- non-existant Host
      api, upstream_url, upstream_host = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = "inexistant.com"})
      assert.falsy(api)
      assert.falsy(upstream_url)
      assert.falsy(upstream_host)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called(2)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called_with({
        message = "API not found with these values",
        request_host = {"inexistant.com"},
        request_path = "/"
      })
      assert.equal(404, ngx.status)
      ngx.status = nil

      -- non-existant request_path with many Host headers
      api, upstream_url, upstream_host = resolver.execute("/some-path", {
        ["Host"] = {"nowhere.com", "inexistant.com"},
        ["X-Host-Override"] = "nowhere.fr"
      })
      assert.falsy(api)
      assert.falsy(upstream_url)
      assert.falsy(upstream_host)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called(3)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called_with({
        message = "API not found with these values",
        request_host = {"nowhere.com", "inexistant.com", "nowhere.fr"},
        request_path = "/some-path"
      })
      assert.equal(404, ngx.status)
      ngx.status = nil

      -- when a later part of the URI has a valid request_path
      api, upstream_url, upstream_host = resolver.execute("/invalid-part/some-path", {})
      assert.falsy(api)
      assert.falsy(upstream_url)
      assert.falsy(upstream_host)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called(4)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called_with({
        message = "API not found with these values",
        request_host = {},
        request_path = "/invalid-part/some-path"
      })
      assert.equal(404, ngx.status)
      ngx.status = nil
    end)
    it("should strip_request_path", function()
      local api = resolver.execute("/strip", {})
      assert.same(APIS_FIXTURES[9], api)

      -- strip when contains pattern characters
      local api, upstream_url, upstream_host = resolver.execute("/strip-me/hello/world", {})
      assert.same(APIS_FIXTURES[10], api)
      assert.equal("http://mockbin.com/hello/world", upstream_url)
      assert.equal("mockbin.com", upstream_host)

      -- only strip first match of request_uri
      api, upstream_url = resolver.execute("/strip-me/strip-me/hello/world", {})
      assert.same(APIS_FIXTURES[10], api)
      assert.equal("http://mockbin.com/strip-me/hello/world", upstream_url)
    end)
    it("should preserve_host", function()
      local api, upstream_url, upstream_host = resolver.execute(DEFAULT_REQUEST_URI, {["Host"] = "preserve-host.com"})
      assert.same(APIS_FIXTURES[11], api)
      assert.equal("http://mockbin.com/", upstream_url)
      assert.equal("preserve-host.com", upstream_host)

      api, upstream_url, upstream_host = resolver.execute(DEFAULT_REQUEST_URI, {
        ["Host"] = {"inexistant.com", "preserve-host.com"},
        ["X-Host-Override"] = "hello.com"
      })
      assert.same(APIS_FIXTURES[11], api)
      assert.equal("http://mockbin.com/", upstream_url)
      assert.equal("preserve-host.com", upstream_host)

      -- No host given to this request, we extract if from the configured upstream_url
      api, upstream_url, upstream_host = resolver.execute("/preserve-host", {})
      assert.same(APIS_FIXTURES[11], api)
      assert.equal("http://mockbin.com/preserve-host", upstream_url)
      assert.equal("mockbin.com", upstream_host)
    end)
    it("should not decode percent-encoded values in URI", function()
      -- they should be forwarded as-is
      local api, upstream_url = resolver.execute("/mockbin/path%2Fwith%2Fencoded/values", {})
      assert.same(APIS_FIXTURES[5], api)
      assert.equal("http://mockbin.com/mockbin/path%2Fwith%2Fencoded/values", upstream_url)

      api, upstream_url = resolver.execute("/strip-me/path%2Fwith%2Fencoded/values", {})
      assert.same(APIS_FIXTURES[10], api)
      assert.equal("http://mockbin.com/path%2Fwith%2Fencoded/values", upstream_url)
    end)
    it("should not recognized request_path if percent-encoded", function()
      local responses = require "kong.tools.responses"
      spy.on(responses, "send_HTTP_NOT_FOUND")
      finally(function()
        responses.send_HTTP_NOT_FOUND:revert()
      end)

      local api = resolver.execute("/some/deep%2Furl", {})
      assert.falsy(api)
      assert.spy(responses.send_HTTP_NOT_FOUND).was_called(1)
      assert.equal(404, ngx.status)
      ngx.status = nil
    end)
    it("should have or not have a trailing slash depending on the request URI", function()
      local api, upstream_url = resolver.execute("/strip/", {})
      assert.same(APIS_FIXTURES[9], api)
      assert.equal("http://mockbin.com/some/path/", upstream_url)

      api, upstream_url = resolver.execute("/strip", {})
      assert.same(APIS_FIXTURES[9], api)
      assert.equal("http://mockbin.com/some/path", upstream_url)

      api, upstream_url = resolver.execute("/mockbin-with-dashes", {})
      assert.same(APIS_FIXTURES[6], api)
      assert.equal("http://mockbin.com/some/path/mockbin-with-dashes", upstream_url)

      api, upstream_url = resolver.execute("/mockbin-with-dashes/", {})
      assert.same(APIS_FIXTURES[6], api)
      assert.equal("http://mockbin.com/some/path/mockbin-with-dashes/", upstream_url)
    end)
    it("should strip the querystring out of the URI", function()
      -- it will be re-inserted by core.handler just before proxying, once all plugins have been run and eventually modified it
      local api, upstream_url = resolver.execute("/?hello=world&foo=bar", {["Host"] = "mockbin.com"})
      assert.same(APIS_FIXTURES[1], api)
      assert.equal("http://mockbin.com/", upstream_url)
    end)
  end)
end)
