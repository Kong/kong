local ee_conf_loader = require("kong.enterprise_edition.conf_loader")

describe("ee conf loader", function()
  describe("validate_admin_gui_authentication()", function()
    pending("returns error if admin_gui_auth value is not supported", function()
      local msgs, err = ee_conf_loader.validate_admin_gui_authentication({ admin_gui_auth =" foo" })

      assert.is_nil(err)

      local expected = { "admin_gui_auth must be 'key-auth', 'basic-auth', " ..
                         "'ldap-auth-advanced' or not set" }
      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_auth_config is set without admin_gui_auth", function()
      local msgs, err = ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth_conf = "{ \"hide_credentials\": true }" })

      assert.is_nil(err)

      local expected = { "admin_gui_auth_conf is set with no admin_gui_auth" }
      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_auth_config is invalid JSON", function()
      local msgs, err = ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth = "basic-auth",
        admin_gui_auth_conf = "{ \"hide_credentials\" = true }",
      })

      assert.is_nil(err)

      local expected = { "admin_gui_auth_conf must be valid json or not set: " ..
                         "Expected colon but found invalid token at " ..
                         "character 22 - { \"hide_credentials\" = true }" }

      assert.same(expected, msgs)
    end)

    it("returns {} if there are no errors", function()
      local msgs, err = ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth = "basic-auth",
        admin_gui_auth_conf = "{ \"hide_credentials\": true }",
      })

      assert.is_nil(err)
      assert.same({}, msgs)
    end)

    it("returns {} if admin gui auth settings are not present", function()
      local msgs, err = ee_conf_loader.validate_admin_gui_authentication({
        some_other_property = "on"
      })

      assert.is_nil(err)
      assert.same({}, msgs)
    end)
  end)

  describe("validate_admin_gui_ssl()", function()
    it("returns errors if ssl_cert is set and doesn't exist", function()
      local conf = {
        admin_gui_listen = { "0.0.0.0:8002", "0.0.0.0:8445 ssl" },
        admin_gui_ssl_cert = "/path/to/cert",
      }

      local msgs = ee_conf_loader.validate_admin_gui_ssl(conf)
      local expected = {
        "admin_gui_ssl_cert_key must be specified",
        "admin_gui_ssl_cert: no such file at /path/to/cert",
      }

      assert.same(expected, msgs)
    end)

    it("returns errors if ssl_cert_key is set and file not found", function()
      local conf = {
        admin_gui_listen = { "0.0.0.0:8002", "0.0.0.0:8445 ssl" },
        admin_gui_ssl_cert_key = "/path/to/cert",
      }

      local msgs = ee_conf_loader.validate_admin_gui_ssl(conf)
      local expected = {
        "admin_gui_ssl_cert must be specified",
        "admin_gui_ssl_cert_key: no such file at /path/to/cert",
      }

      assert.same(expected, msgs)
    end)

    it("returns {} if ssl_cert and ssl_cert_key are not set", function()
      local conf = {
        some_other_key = "foo",
        admin_gui_listen = { "0.0.0.0:8002" },
      }

      local msgs = ee_conf_loader.validate_admin_gui_ssl(conf)
      assert.same({}, msgs)
    end)

    it("returns {} if admin_gui_listen doesn't include SSL", function()
      local conf = {
        admin_gui_listen = { "0.0.0.0:8002" },
        admin_gui_ssl_cert_key = "/path/to/cert",
      }

      local msgs = ee_conf_loader.validate_admin_gui_ssl(conf)
      assert.same({}, msgs)
    end)
  end)
end)
