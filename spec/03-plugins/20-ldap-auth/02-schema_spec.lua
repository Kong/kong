local schema_def = require "kong.plugins.ldap-auth.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("Plugin: ldap-auth (schema)", function()
  describe("errors", function()
    it("requires ldaps and start_tls to be mutually exclusive", function()
      local ok, err = v({ldap_host = "none", ldap_port = 389, ldaps = true, start_tls = true, base_dn="ou=users", attribute="cn"}, schema_def)
      assert.falsy(ok)
      assert.equals("'ldaps' and 'start_tls' cannot be enabled simultaneously", err.config["@entity"][1])
    end)
  end)
end)


