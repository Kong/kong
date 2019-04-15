local validate_entity = require("spec.helpers").validate_plugin_config_schema
local ldap_schema = require("kong.plugins.ldap-auth-advanced.schema")


describe("ldap auth advanced schema", function()
  it("should pass with default configuration parameters", function()
    local ok, err = validate_entity({ base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com", attribute = "uuid",
                                      ldap_host = "host" }, ldap_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("should fail with both config.ssl and config.start_tls options enabled", function()
    local ok, err = validate_entity({ base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com", attribute = "uuid",
                                      ldap_host = "host", ssl = true, start_tls = true }, ldap_schema)

    local expected = {
      "SSL and StartTLS cannot be enabled simultaneously."
    }
    assert.is_falsy(ok)
    assert.is_same(expected, err["@entity"])
  end)

  it("should pass with parameters config.ssl enabled and config.start_tls disbled", function()
    local ok, err = validate_entity({ base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com", attribute = "uuid", 
                                      ldap_host = "host", ssl = true, start_tls = false }, ldap_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("should pass with parameters config.ssl disabled and config.start_tls enabled", function()
    local ok, err = validate_entity({ base_dn = "ou=scientists,dc=ldap,dc=mashape,dc=com", attribute = "uuid",
                                      ldap_host = "host", ssl = false, start_tls = true }, ldap_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
end)
