local resolver_access = require "kong.resolver.access"

-- Stubs
require "kong.tools.ngx_stub"
local APIS_FIXTURES = {
  {name = "mockbin", request_host = "mockbin.com", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_host = "mockbin-auth.com", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_host = "*.wildcard.com", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_host = "wildcard.*", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_path = "/mockbin", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_path = "/mockbin-with-dashes", upstream_url = "http://mockbin.com"},
  {name = "mockbin", request_path = "/some/deep/url", upstream_url = "http://mockbin.com"}
}
_G.dao = {
  apis = {
    find_all = function()
      return APIS_FIXTURES
    end
  }
}

local apis_dics

describe("Resolver Access", function()
  describe("load_apis_in_memory()", function()
    it("should retrieve all APIs in datastore and return them organized", function()
      apis_dics = resolver_access.load_apis_in_memory()
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
      assert.equal(3, #apis_dics.request_path_arr)
      for _, item in ipairs(apis_dics.request_path_arr) do
        assert.truthy(item.strip_request_path_pattern)
        assert.truthy(item.request_path)
        assert.truthy(item.api)
      end
      assert.equal("/mockbin", apis_dics.request_path_arr[1].strip_request_path_pattern)
      assert.equal("/mockbin%-with%-dashes", apis_dics.request_path_arr[2].strip_request_path_pattern)
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
  describe("find_api_by_request_path()", function()
    it("should return nil when no matching API for that URI", function()
      local api = resolver_access.find_api_by_request_path("/", apis_dics.request_path_arr)
      assert.falsy(api)
    end)
    it("should return the API for a matching URI", function()
      local api = resolver_access.find_api_by_request_path("/mockbin", apis_dics.request_path_arr)
      assert.same(APIS_FIXTURES[5], api)

      api = resolver_access.find_api_by_request_path("/mockbin-with-dashes", apis_dics.request_path_arr)
      assert.same(APIS_FIXTURES[6], api)

      api = resolver_access.find_api_by_request_path("/mockbin-with-dashes/and/some/uri", apis_dics.request_path_arr)
      assert.same(APIS_FIXTURES[6], api)

      api = resolver_access.find_api_by_request_path("/dashes-mockbin", apis_dics.request_path_arr)
      assert.falsy(api)

      api = resolver_access.find_api_by_request_path("/some/deep/url", apis_dics.request_path_arr)
      assert.same(APIS_FIXTURES[7], api)
    end)
  end)
  describe("find_api_by_request_host()", function()
    it("should return nil and a list of all the Host headers in the request when no API was found", function()
      local api, all_hosts = resolver_access.find_api_by_request_host({
        Host = "foo.com",
        ["X-Host-Override"] = {"bar.com", "hello.com"}
      }, apis_dics)
      assert.falsy(api)
      assert.same({"foo.com", "bar.com", "hello.com"}, all_hosts)
    end)
    it("should return an API when one of the Host headers matches", function()
      local api = resolver_access.find_api_by_request_host({Host = "mockbin.com"}, apis_dics)
      assert.same(APIS_FIXTURES[1], api)

      api = resolver_access.find_api_by_request_host({Host = "mockbin-auth.com"}, apis_dics)
      assert.same(APIS_FIXTURES[2], api)
    end)
    it("should return an API when one of the Host headers matches a wildcard dns", function()
      local api = resolver_access.find_api_by_request_host({Host = "wildcard.com"}, apis_dics)
      assert.same(APIS_FIXTURES[4], api)
      api = resolver_access.find_api_by_request_host({Host = "wildcard.fr"}, apis_dics)
      assert.same(APIS_FIXTURES[4], api)

      api = resolver_access.find_api_by_request_host({Host = "foobar.wildcard.com"}, apis_dics)
      assert.same(APIS_FIXTURES[3], api)
      api = resolver_access.find_api_by_request_host({Host = "barfoo.wildcard.com"}, apis_dics)
      assert.same(APIS_FIXTURES[3], api)
    end)
  end)
  describe("strip_request_path()", function()
    it("should strip the api's request_path from the requested URI", function()
      assert.equal("/status/200", resolver_access.strip_request_path("/mockbin/status/200", apis_dics.request_path_arr[1].strip_request_path_pattern))
      assert.equal("/status/200", resolver_access.strip_request_path("/mockbin-with-dashes/status/200", apis_dics.request_path_arr[2].strip_request_path_pattern))
      assert.equal("/", resolver_access.strip_request_path("/mockbin", apis_dics.request_path_arr[1].strip_request_path_pattern))
      assert.equal("/", resolver_access.strip_request_path("/mockbin/", apis_dics.request_path_arr[1].strip_request_path_pattern))
    end)
    it("should only strip the first pattern", function()
      assert.equal("/mockbin/status/200/mockbin", resolver_access.strip_request_path("/mockbin/mockbin/status/200/mockbin", apis_dics.request_path_arr[1].strip_request_path_pattern))
    end)
  end)
end)
