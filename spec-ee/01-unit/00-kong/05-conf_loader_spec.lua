-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local conf_loader = require "kong.conf_loader"
local ee_conf_loader = require("kong.enterprise_edition.conf_loader")
local helpers = require "spec.helpers"
local pl_file = require "pl.file"

local openssl = require "resty.openssl"

local fips_test, non_fips_test = pending, it
if openssl.set_fips_mode(true) and openssl.get_fips_mode() then
  fips_test, non_fips_test = it, pending
end

describe("Configuration loader - enterprise", function()
  it("loads the defaults", function()
    local conf = assert(conf_loader())
    assert.same({"0.0.0.0:8003", "0.0.0.0:8446 ssl"}, conf.portal_gui_listen)
    assert.same({"0.0.0.0:8004", "0.0.0.0:8447 ssl"}, conf.portal_api_listen)

    assert.equal("logs/portal_gui_access.log", conf.portal_gui_access_log)
    assert.equal("logs/portal_gui_error.log", conf.portal_gui_error_log)
    assert.equal("logs/portal_api_access.log", conf.portal_api_access_log)
    assert.equal("logs/portal_api_error.log", conf.portal_api_error_log)
    assert.equal(0, #conf.portal_gui_ssl_cert)
    assert.equal(0, #conf.portal_gui_ssl_cert_key)
    assert.equal(0, #conf.portal_api_ssl_cert)
    assert.equal(0, #conf.portal_api_ssl_cert_key)
    assert.is_nil(getmetatable(conf))
  end)

  it("loads a given file, with higher precedence", function()
    local conf = assert(conf_loader(helpers.test_conf_path))
    -- defaults
    assert.equal("on", conf.nginx_daemon)
    -- overrides
    assert.same({"0.0.0.0:9003", "0.0.0.0:9446 ssl"}, conf.portal_gui_listen)
    assert.equal("127.0.0.1:9003", conf.portal_gui_host)
    assert.equal("http", conf.portal_gui_protocol)
    assert.same({"0.0.0.0:9004", "0.0.0.0:9447 ssl"}, conf.portal_api_listen)
    assert.equal("http://127.0.0.1:9004", conf.portal_api_url)
    assert.is_nil(getmetatable(conf))
  end)

  it("extracts flags, ports and listen ips from portal_listen", function()
    local conf = assert(conf_loader())
    -- portal is disabled by default
    assert.equal(nil, conf.portal_gui_listeners)
    assert.equal(nil, conf.portal_api_listeners)
  end)

  it("attaches prefix paths", function()
    local conf = assert(conf_loader())
    assert.equal("/usr/local/kong/ssl/portal-gui-kong-default.crt", conf.portal_gui_ssl_cert_default)
    assert.equal("/usr/local/kong/ssl/portal-gui-kong-default.key", conf.portal_gui_ssl_cert_key_default)
    assert.equal("/usr/local/kong/ssl/portal-api-kong-default.crt", conf.portal_api_ssl_cert_default)
    assert.equal("/usr/local/kong/ssl/portal-api-kong-default.key", conf.portal_api_ssl_cert_key_default)
  end)

  describe("validations", function()
    it("enforces enforce_rbac values", function()
      local conf, _, errors = conf_loader(nil, {
        enforce_rbac = "foo",
      })
      assert.equal(1, #errors)
      assert.is_nil(conf)
    end)

    it("enforces admin_gui_auth if admin_gui_auth_conf is present", function()
      local conf, err = conf_loader(nil, {
        admin_gui_auth_conf = "{ \"hide_credentials\": true }",
        enforce_rbac = "on",
      })
      assert.is_nil(conf)
      assert.equal("admin_gui_auth_conf is set with no admin_gui_auth", err)
    end)

    it("enforces valid json for admin_gui_auth_conf", function()
      local conf, err = conf_loader(nil, {
        admin_gui_auth = "basic-auth",
        admin_gui_auth_conf = "{ \"hide_credentials\": derp }",
        enforce_rbac = "on",
      })
      assert.is_nil(conf)
      assert.equal("admin_gui_auth_conf must be valid json or not set: Expected value but found invalid token at character 23 - { \"hide_credentials\": derp }", err)
    end)

    it("#flaky enforces listen addresses format", function()
      local err_str = "must be of form: [off] | <ip>:<port> [ssl] [http2] [proxy_protocol] [deferred] [bind] [reuseport] [backlog=%d+] [ipv6only=on] [ipv6only=off] [so_keepalive=on] [so_keepalive=off] [so_keepalive=%w*:%w*:%d*], [... next entry ...]"
      local conf, err = conf_loader(nil, {
        portal = "on",
        smtp_mock = "on",
        portal_gui_listen = "127.0.0.1",
        portal_token_exp = 21600,
      })
      assert.is_nil(conf)
      assert.equal("portal_gui_listen " .. err_str, err)

      conf, err = conf_loader(nil, {
        portal = "on",
        smtp_mock = "on",
        portal_api_listen = "127.0.0.1",
        portal_token_exp = 21600,
      })
      assert.is_nil(conf)
      assert.equal("portal_api_listen " .. err_str, err)
    end)

    it("enforces positive number for portal_token_exp ", function()
      local conf, err = conf_loader(nil, {
        portal = "on",
        smtp_mock = "on",
        portal_api_listen = "0.0.0.0:8004, 0.0.0.0:8447 ssl",
        portal_token_exp = 0,
      })
      assert.is_nil(conf)
      assert.equal("portal_token_exp must be a positive number", err)

      conf, err = conf_loader(nil, {
        portal = "on",
        smtp_mock = "on",
        portal_api_listen = "0.0.0.0:8004, 0.0.0.0:8447 ssl",
        portal_token_exp = "whut",
      })
      assert.is_nil(conf)
      assert.equal("portal_token_exp must be a positive number", err)

      conf, err = conf_loader(nil, {
        portal = "on",
        smtp_mock = "on",
        portal_api_listen = "0.0.0.0:8004, 0.0.0.0:8447 ssl",
        portal_token_exp = -1,
      })
      assert.is_nil(conf)
      assert.equal("portal_token_exp must be a positive number", err)

      conf, err = conf_loader(nil, {
        portal = "on",
        smtp_mock = "on",
        portal_api_listen = "0.0.0.0:8004, 0.0.0.0:8447 ssl",
        portal_token_exp = false,
      })
      assert.is_nil(conf)
      assert.equal("portal_token_exp must be a positive number", err)
    end)

    it("enforces smtp credentials when smtp_mock is off", function()
      local _, err = conf_loader(nil, {
        portal = "off",
        smtp_mock = "off",
      })
      assert.is_nil(err)

      local conf, err = conf_loader(nil, {
        portal = "off",
        smtp_mock = "off",
        smtp_auth_type = "weirdo",
      })
      assert.is_nil(conf)
      assert.equal("smtp_auth_type must be 'plain', 'login', or nil", err)

      local conf, err = conf_loader(nil, {
        portal = "off",
        smtp_mock = "off",
        smtp_auth_type = "plain",
      })
      assert.is_nil(conf)
      assert.equal("smtp_username must be set when using smtp_auth_type", err)

      local conf, err = conf_loader(nil, {
        portal = "off",
        smtp_mock = "off",
        smtp_auth_type = "plain",
        smtp_username = "meme_lord"
      })
      assert.is_nil(conf)
      assert.equal("smtp_password must be set when using smtp_auth_type", err)

      local _, err = conf_loader(nil, {
        portal = "off",
        smtp_mock = "off",
        smtp_auth_type = "plain",
        smtp_username = "meme_lord",
        smtp_password = "dank memes"
      })
      assert.is_nil(err)
    end)

    it("enforces portal_session_conf must be valid json", function()
      local _, err = conf_loader(nil, {
        portal = "on",
        portal_auth = "basic-auth",
        portal_session_conf = "{ \"cookie_name\": \"portal_session\", \"secret\": \"super-secret\", \"cookie_secure\": false, \"storage\": \"kong\" }",
      })
      assert.is_nil(err)

      local conf, err = conf_loader(nil, {
        portal = "on",
        portal_auth = "basic-auth",
        portal_session_conf = "wow",
      })
      assert.is_nil(conf)
      assert.equal("portal_session_conf must be valid json or not set: Expected value but found invalid token at character 1 - wow", err)
    end)

    it("enforces portal_session_conf when portal_auth is set to something other than openid-connect", function()
      local _, err = conf_loader(nil, {
        portal = "on",
        portal_auth = "basic-auth",
        portal_session_conf = "{ \"cookie_name\": \"portal_session\", \"secret\": \"super-secret\", \"cookie_secure\": false, \"storage\": \"kong\" }",
      })
      assert.is_nil(err)

      local _, err = conf_loader(nil, {
        portal = "on",
        portal_auth = "openid-connect",
      })
      assert.is_nil(err)

      local conf, err = conf_loader(nil, {
        portal = "on",
        portal_auth = "basic-auth",
      })
      assert.is_nil(conf)
      assert.equal("portal_session_conf is required when portal_auth is set to basic-auth", err)
    end)

    it("enforces portal_session_conf 'secret' must be type 'string'", function()
      local _, err = conf_loader(nil, {
        portal = "on",
        portal_auth = "basic-auth",
        portal_session_conf = "{ \"secret\": \"super-secret\" }",
      })
      assert.is_nil(err)

      local conf, err = conf_loader(nil, {
        portal = "on",
        portal_auth = "basic-auth",
        portal_session_conf = "{}",
      })
      assert.is_nil(conf)
      assert.equal("portal_session_conf 'secret' must be type 'string'", err)
    end)

    it("enforces ssl when pg_iam_auth is enabled", function ()
      local conf = conf_loader(nil, {
        pg_iam_auth = "on",
      })

      assert.equal(true, conf.pg_ssl)
      assert.equal(true, conf.pg_ssl_required)
    end)

    it("deny mtls config when pg_iam_auth is enabled", function ()
      local conf, err = conf_loader(nil, {
        pg_iam_auth = "on",
        pg_ssl_cert = "path/to/cert",
        pg_ssl_cert_key = "path/to/key"
      })

      assert.is_nil(conf)
      assert.equal("mTLS connection to postgres cannot be used when pg_iam_auth is enabled, so pg_ssl_cert and pg_ssl_cert_key must not be specified", err)
    end)
  end)

  describe("vitals strategy", function()
    it("disabled by default", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
      }))
      assert.equal("database", conf.vitals_strategy)
    end)
    it("can be set to database", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        vitals_strategy = "database",
      }))
      assert.equal("database", conf.vitals_strategy)
    end)
    it("can be set to prometheus", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        vitals_strategy = "prometheus",
        vitals_tsdb_address = "127.0.0.1:9090",
        vitals_statsd_address = "127.0.0.1:8125",
      }))
      assert.equal("prometheus", conf.vitals_strategy)
    end)
    it("can't be set to other strategy", function()
      local ok, err = conf_loader(helpers.test_conf_path, {
        vitals_strategy = "sometsdb"
      })
      assert.is_nil(ok)
      assert.same("vitals_strategy must be one of \"database\", \"prometheus\", or \"influxdb\"", err)
    end)
    it("errors if vitals_tsdb_address and vitals_statsd_address not set " ..
       "with prometheus strategy", function()

      local expected = "vitals_statsd_address must be defined " ..
      "when vitals_strategy is set to \"prometheus\""
      local ok, err = conf_loader(helpers.test_conf_path, {
        vitals_strategy = "prometheus",
        vitals_tsdb_address = "127.0.0.1:9090",
      })
      assert.is_nil(ok)
      assert.same(expected, err)

      for _, strategy in ipairs({"prometheus", "influxdb"}) do
        expected = 'vitals_tsdb_address must be defined when vitals_strategy = "prometheus" or "influxdb"'
        local ok, err = conf_loader(helpers.test_conf_path, {
          vitals_strategy = strategy,
        })
        assert.is_nil(ok)
        assert.same(expected, err)
      end

      local ok, err = conf_loader(helpers.test_conf_path, {
        vitals_strategy = "prometheus",
      })
      assert.is_nil(ok)
      assert.same(expected, err)
    end)
  end)
end)

describe("ee conf loader", function()
  local msgs
  before_each(function()
    msgs = {}
  end)

  describe("validate_enforce_rbac()", function()
    it("returns error if admin_gui_auth is set and enforce_rbac off", function()
      local _, err = ee_conf_loader.validate_enforce_rbac({ admin_gui_auth = "basic-auth",
                                             enforce_rbac = "off",
                                           })

      local expected = "RBAC authorization is off" ..
                         " and admin_gui_auth is 'basic-auth'"

      assert.same(expected, err)
    end)

    it("returns error if admin_gui_auth not set and enforce_rbac on", function()
      local _, err = ee_conf_loader.validate_enforce_rbac({ enforce_rbac = "on" })

      local expected = "RBAC authorization is on" ..
                         " and admin_gui_auth is 'nil'"

      assert.same(expected, err)
    end)

    it("returns nil if admin_gui_auth not set and enforce_rbac off", function()
      local _, err = ee_conf_loader.validate_enforce_rbac({ enforce_rbac = "off" })

      assert.is_nil(err)
    end)

    it("returns nil if admin_gui_auth is set and enforce_rbac on", function()
      local _, err = ee_conf_loader.validate_enforce_rbac({ admin_gui_auth = "basic-auth",
                                             enforce_rbac = "on" })

      assert.is_nil(err)
    end)
  end)

  describe("validate_admin_gui_authentication()", function()
    it("returns error if admin_gui_auth value is not supported", function()
      ee_conf_loader.validate_admin_gui_authentication({ admin_gui_auth ="foo",
                                                         enforce_rbac = true,
                                                       }, msgs)

      local expected = { "admin_gui_auth must be 'key-auth', 'basic-auth', " ..
                         "'ldap-auth-advanced', 'openid-connect' or not set" }
      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_auth_config is set without admin_gui_auth", function()
      ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth_conf = "{ \"hide_credentials\": true }" }, msgs)

      local expected = { "admin_gui_auth_conf is set with no admin_gui_auth" }
      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_auth_config is invalid JSON", function()
      ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth = "basic-auth",
        admin_gui_auth_conf = "{ \"hide_credentials\" = true }",
        enforce_rbac = true,
      }, msgs)

      local expected = { "admin_gui_auth_conf must be valid json or not set: " ..
                         "Expected colon but found invalid token at " ..
                         "character 22 - { \"hide_credentials\" = true }" }

      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_auth_password_complexity is set without basic-auth", function()
      ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth_password_complexity = "{ \"min\": \"disabled,24,11,9,8\", \"match\": 3 }"
      }, msgs)

      local expected = { "admin_gui_auth_password_complexity is set without basic-auth" }
      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_auth_password_complexity is invalid JSON", function()
      ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth = "basic-auth",
        admin_gui_auth_password_complexity = "{ \"min\"= \"disabled,24,11,9,8\", \"match\": 3 }",
        enforce_rbac = true,
      }, msgs)

      local expected = { "admin_gui_auth_password_complexity must be valid json or not set: " ..
                         "Expected colon but found invalid token at " ..
                         "character 8 - { \"min\"= \"disabled,24,11,9,8\", \"match\": 3 }" }

      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_auth is on but rbac is off", function()
      ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth = "basic-auth",
        enforce_rbac = false,
      }, msgs)

       local expected = { "enforce_rbac must be enabled when admin_gui_auth " ..
                         "is enabled" }

      assert.same(expected, msgs)
    end)

    it("returns {} if there are no errors", function()
      ee_conf_loader.validate_admin_gui_authentication({
        admin_gui_auth = "basic-auth",
        admin_gui_auth_conf = "{ \"hide_credentials\": true }",
        enforce_rbac = true,
      }, msgs)

      assert.same({}, msgs)
    end)

    it("returns {} if admin gui auth settings are not present", function()
      ee_conf_loader.validate_admin_gui_authentication({
        some_other_property = "on"
      }, msgs)

      assert.same({}, msgs)
    end)

    it("return error when admin_auto_create is not boolean", function()
      local conf, err = conf_loader(nil, {
        admin_gui_auth = "openid-connect",
        admin_gui_auth_conf = '{"issuer":"http://localhost","admin_claim":"email","client_id":["client_id"],"client_secret":["client_secret"],"authenticated_groups_claim":["groups"],"ssl_verify":false,"leeway":60,"redirect_uri":["http://localhost"],"login_redirect_uri":["http://localhost"],"logout_methods":["GET","DELETE"],"logout_query_arg":"logout","logout_redirect_uri":["http://localhost"],"scopes":["openid","profile","email","offline_access"],"auth_methods":["authorization_code"],"admin_auto_create_rbac_token_disabled":false,"admin_auto_create":"true" }',
        enforce_rbac = "on",
      })
      assert.is_nil(conf)
      assert.equal("admin_auto_create must be boolean", err)
    end)
  end)

  describe("validate_admin_gui_session()", function()
    it("returns error if admin_gui_auth is set without admin_gui_session_conf", function()
      ee_conf_loader.validate_admin_gui_session({
        admin_gui_auth = "basic-auth",
      }, msgs)

      local expected = { "admin_gui_session_conf must be set when admin_gui_auth is enabled" }
      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_session_conf is set with no admin_gui_auth", function()
      ee_conf_loader.validate_admin_gui_session({
        admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
      }, msgs)

      local expected = { "admin_gui_session_conf is set with no admin_gui_auth" }
      assert.same(expected, msgs)
    end)

    it("returns error if admin_gui_session_conf is invalid json", function()
      ee_conf_loader.validate_admin_gui_session({
        admin_gui_auth = "basic-auth",
        admin_gui_session_conf = "{ 'secret': 'i-am-invalid-json' }",
      }, msgs)

      local expected = { "admin_gui_session_conf must be valid json or not set: " ..
                         "Expected object key string but found invalid token at " ..
                         "character 3 - { 'secret': 'i-am-invalid-json' }" }
      assert.same(expected, msgs)
    end)

    it("defaults sessions storage to 'kong'", function()
      local conf = {
        admin_gui_auth = "basic-auth",
        admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
      }

      ee_conf_loader.validate_admin_gui_session(conf, msgs)

      assert.equal("kong", conf.admin_gui_session_conf.storage)
      assert.same({}, msgs)
    end)
  end)

  describe("SSL", function()
    it("accepts and decodes valid base64 values", function()
      local ssl_fixtures = require "spec.fixtures.ssl"
      local cert = ssl_fixtures.cert
      local key = ssl_fixtures.key
      local keyring_pub_key = helpers.file.read("spec-ee/fixtures/keyring/crypto_cert.pem")
      local keyring_priv_key = helpers.file.read("spec-ee/fixtures/keyring/crypto_key.pem")

      local cert_and_keys = {
        portal_gui_ssl_cert         = { cert },
        portal_gui_ssl_cert_key     = { key },
        portal_api_ssl_cert         = { cert },
        portal_api_ssl_cert_key     = { key },
        keyring_recovery_public_key = keyring_pub_key,
        keyring_public_key          = keyring_pub_key,
        keyring_private_key         = keyring_priv_key,
      }

      local conf_properties = {
        portal_gui_listen = { "0.0.0.0:8446 ssl" },
        portal_api_listen = { "0.0.0.0:8447 ssl" },
        keyring_enabled = "on",
      }

      for n, v in pairs(cert_and_keys) do
        if type(v) == "table" then
          conf_properties[n] = { ngx.encode_base64(v[1]) }
        else
          conf_properties[n] = ngx.encode_base64(v)
        end
      end

      ee_conf_loader.validate_portal_ssl(conf_properties, msgs)
      ee_conf_loader.validate_keyring(conf_properties, msgs)

      assert.same({}, msgs)
      for name, decoded_v in pairs(cert_and_keys) do
        local values = conf_properties[name]
        if type(values) == "table" then
          for i = 1, #values do
            local expected_v = type(decoded_v) == "table" and decoded_v[1] or decoded_v
            assert.equals(expected_v, values[i])
          end
        end

        if type(values) == "string" then
          assert.equals(decoded_v, values)
        end
      end
    end)
  end)

  describe("validate_tracing", function()
    it("requires a write endpoint when enabled", function()
      ee_conf_loader.validate_tracing({
        tracing = true,
      }, msgs)

      local expected = {
        "'tracing_write_endpoint' must be defined when 'tracing' is enabled"
      }

      assert.same(expected, msgs)
    end)
  end)

  describe("portal_app_auth", function()
    it("no errors for unset", function()
      ee_conf_loader.validate_portal_app_auth({
      }, msgs)


      assert.same({}, msgs)
    end)

    it("accepts kong-oauth", function()
      ee_conf_loader.validate_portal_app_auth({
        portal_app_auth = "kong-oauth2",
      }, msgs)


      assert.same({}, msgs)
    end)

    it("does not accept invalid string", function()
      ee_conf_loader.validate_portal_app_auth({
        portal_app_auth = "not-valid",
      }, msgs)

      local expected = {
        "portal_app_auth must be not set or one of: kong-oauth2, external-oauth2"
      }

      assert.same(expected, msgs)
    end)
  end)

  describe("portal_app_auth", function()
    it("no errors for unset", function()
      ee_conf_loader.validate_portal_app_auth({
      }, msgs)


      assert.same({}, msgs)
    end)

    it("accepts kong-oauth", function()
      ee_conf_loader.validate_portal_app_auth({
        portal_app_auth = "kong-oauth2",
      }, msgs)


      assert.same({}, msgs)
    end)

    it("does not accept invalid string", function()
      ee_conf_loader.validate_portal_app_auth({
        portal_app_auth = "not-valid",
      }, msgs)

      local expected = {
        "portal_app_auth must be not set or one of: kong-oauth2, external-oauth2"
      }

      assert.same(expected, msgs)
    end)
  end)

  describe("#fips", function()
    local license_env

    setup(function()                                                                                                                             
      license_env = os.getenv("KONG_LICENSE_DATA")                                                                                               
      helpers.setenv("KONG_LICENSE_DATA", pl_file.read("spec-ee/fixtures/mock_license.json"))                                                    
    end)
                                                                                                                                                 
    teardown(function()                                                                                                                          
      if type(license_env) == "string" then                                                                                                      
        helpers.setenv("KONG_LICENSE_DATA", license_env)                                                                                         
      end                                                                                                                                        
    end)

    fips_test("with fips: validates correctly", function()
      local conf, err = conf_loader(nil, {
        fips = true,
      })
      assert.is_nil(err)

      assert.equal(conf.ssl_cipher_suite, "fips")
    end)

    non_fips_test("without fips: validates correctly", function()
      local _, err = conf_loader(nil, {
        fips = false,
      })
      assert.is_nil(err)

      local _, err = conf_loader(nil, {
        fips = true,
      })

      assert.match("cannot enable FIPS mode: provider.load", err)
    end)
  end)
end)

describe("deprecated properties", function()
  it("admin_api_uri should map to admin_gui_api_url", function()
    local conf, err = assert(conf_loader(nil, {
      admin_api_uri = "http://localhost:8001/admin/api",
    }))

    assert.equal("http://localhost:8001/admin/api", conf.admin_gui_api_url)
    assert.equal(nil, err)

    conf, err = assert(conf_loader(nil, {
      admin_api_uri = "https://localhost:8001/",
      admin_gui_api_url = "http://admin.api:8001/api",
    }))

    assert.equal("http://admin.api:8001/api", conf.admin_gui_api_url)
    assert.equal(nil, err)
  end)
end)

describe("admin_gui_ssl_protocols", function()
  it("sets admin_gui_ssl_protocols to TLS 1.1-1.3 by default", function()
    local conf, err = conf_loader()
    assert.is_nil(err)
    assert.is_table(conf)

    assert.equal("TLSv1.1 TLSv1.2 TLSv1.3", conf.admin_gui_ssl_protocols)
  end)

  it("sets admin_gui_ssl_protocols to user specified value", function()
    local conf, err = conf_loader(nil, {
      admin_gui_ssl_protocols = "TLSv1.1"
    })
    assert.is_nil(err)
    assert.is_table(conf)

    assert.equal("TLSv1.1", conf.admin_gui_ssl_protocols)
  end)
end)

describe("portal_gui_ssl_protocols", function()
  it("sets portal_gui_ssl_protocols to TLS 1.1-1.3 by default", function()
    local conf, err = conf_loader()
    assert.is_nil(err)
    assert.is_table(conf)

    assert.equal("TLSv1.1 TLSv1.2 TLSv1.3", conf.portal_gui_ssl_protocols)
  end)

  it("sets portal_gui_ssl_protocols to user specified value", function()
    local conf, err = conf_loader(nil, {
      portal_gui_ssl_protocols = "TLSv1.1"
    })
    assert.is_nil(err)
    assert.is_table(conf)

    assert.equal("TLSv1.1", conf.portal_gui_ssl_protocols)
  end)
end)

describe("portal_api_ssl_protocols", function()
  it("sets portal_api_ssl_protocols to TLS 1.1-1.3 by default", function()
    local conf, err = conf_loader()
    assert.is_nil(err)
    assert.is_table(conf)

    assert.equal("TLSv1.1 TLSv1.2 TLSv1.3", conf.portal_api_ssl_protocols)
  end)

  it("sets portal_api_ssl_protocols to user specified value", function()
    local conf, err = conf_loader(nil, {
      portal_api_ssl_protocols = "TLSv1.1"
    })
    assert.is_nil(err)
    assert.is_table(conf)
    
    assert.equal("TLSv1.1", conf.portal_api_ssl_protocols)
  end)
end)
