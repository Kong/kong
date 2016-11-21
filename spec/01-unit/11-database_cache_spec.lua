local cache = require "kong.tools.database_cache"

describe("Database cache", function()

  it("returns a valid API cache key", function()
    assert.are.equal("apis:httpbin.org", cache.api_key("httpbin.org"))
  end)

  it("returns a valid PLUGIN cache key", function()
    assert.are.equal("plugins:authentication:api123:app123", cache.plugin_key("authentication", "api123", "app123"))
    assert.are.equal("plugins:authentication:api123", cache.plugin_key("authentication", "api123"))
  end)

  it("returns a valid KeyAuthCredential cache key", function()
    assert.are.equal("keyauth_credentials:username", cache.keyauth_credential_key("username"))
  end)

  it("returns a valid BasicAuthCredential cache key", function()
    assert.are.equal("basicauth_credentials:username", cache.basicauth_credential_key("username"))
  end)

  it("returns a valid HmacAuthCredential cache key", function()
    assert.are.equal("hmacauth_credentials:username", cache.hmacauth_credential_key("username"))
  end)

  it("returns a valid JWTAuthCredential cache key", function()
    assert.are.equal("jwtauth_credentials:hello", cache.jwtauth_credential_key("hello"))
  end)

  it("returns a valid LDAPAuthcredentials cache key", function()
    assert.are.equal("ldap_credentials_0c704b70-3f30-49ad-9418-3968e53c8d98:username", cache.ldap_credential_key("0c704b70-3f30-49ad-9418-3968e53c8d98", "username"))
  end)

end)
