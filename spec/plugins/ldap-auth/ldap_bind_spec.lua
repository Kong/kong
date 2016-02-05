local ldap_authentication = require "kong.plugins.ldap-auth.ldap_authentication"

describe("ldap bind authentication", function()
  local conf = {ldap_protocol = "ldap", ldap_host = "ldap.forumsys.com", ldap_port = "389", start_tls = false, base_dn = "dc=example,dc=com", attribute = "uid"}
  it("should bind to ldap server for valid credential for user einstein", function()
    local isAuthorized, err = ldap_authentication.authenticate("einstein", "password", conf)
    assert.TRUE(isAuthorized)
    assert.FALSY(err)
  end)
  
  it("should bind to ldap server for valid credential for user newton", function()
    local isAuthorized, err = ldap_authentication.authenticate("newton", "password", conf)
    assert.TRUE(isAuthorized)
    assert.FALSY(err)
  end)
  
  it("should not bind to ldap server for invalid credential", function()
    local isAuthorized, err = ldap_authentication.authenticate("einstein", "passwordss", conf)
    assert.FALSE(isAuthorized)
    assert.truthy(err)
  end)
end)
