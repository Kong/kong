local validate_entity = require("kong.dao.schemas_validation").validate_entity
local ldap_auth_schema = require "kong.plugins.ldap-auth.schema"

describe("Plugin: ldap-auth (schema)", function()
  describe("errors", function()
    it("requires ldaps and start_tls to be mutually exclusive", function()
      local ok, errors, err = validate_entity({ldap_host = "none", ldap_port = "389", ldaps = true, start_tls = true, base_dn="ou=users", attribute="cn"}, ldap_auth_schema)
      assert.False(ok)
      assert.equal("LDAPS and StartTLS cannot be enabled simultaneously. You need to enable only one of the two.", tostring(err))
    end)
  end)
end)


