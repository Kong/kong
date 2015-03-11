local cache = require "kong.tools.cache"

describe("Cache", function()

  it("should return a valid API cache key", function()
    assert.are.equal("apis/httpbin.org", cache.api_key("httpbin.org"))
  end)

  it("should return a valid PLUGIN cache key", function()
    assert.are.equal("plugins/authentication/api123/app123", cache.plugin_key("authentication", "api123", "app123"))
    assert.are.equal("plugins/authentication/api123", cache.plugin_key("authentication", "api123"))
  end)

  it("should return a valid Application cache key", function()
    assert.are.equal("applications/username", cache.application_key("username"))
  end)

end)