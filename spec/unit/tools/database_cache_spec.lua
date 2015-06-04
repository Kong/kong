local cache = require "kong.tools.database_cache"

describe("Database cache", function()

  it("should return a valid API cache key", function()
    assert.are.equal("apis/httpbin.org", cache.api_key("httpbin.org"))
  end)

  it("should return a valid PLUGIN cache key", function()
    assert.are.equal("plugins_configurations/authentication/api123/app123", cache.plugin_configuration_key("authentication", "api123", "app123"))
    assert.are.equal("plugins_configurations/authentication/api123", cache.plugin_configuration_key("authentication", "api123"))
  end)

  it("should return a valid KeyAuthCredential cache key", function()
    assert.are.equal("keyauth_credentials/username", cache.keyauth_credential_key("username"))
  end)

  it("should return a valid BasicAuthCredential cache key", function()
    assert.are.equal("basicauth_credentials/username", cache.basicauth_credential_key("username"))
  end)

  it("should return a valid requests cache key", function()
    assert.are.equal("requests", cache.requests_key())
  end)

end)
