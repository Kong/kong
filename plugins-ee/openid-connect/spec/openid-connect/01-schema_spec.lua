-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils   = require "kong.tools.utils"
local helpers = require "spec.helpers"
local Entity  = require "kong.db.schema.entity"
local plugins_schema_def = require "kong.db.schema.entities.plugins"

local PLUGIN_NAME = "openid-connect"
local oidc_schema = require("kong.plugins."..PLUGIN_NAME..".schema")


local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema

  function validate(data, extra)
    return validate_entity(data, oidc_schema, extra)
  end
end


local process_plugin_config do
  local plugins_schema = assert(Entity.new(plugins_schema_def))
  assert(plugins_schema:new_subschema(oidc_schema.name, oidc_schema))

  function process_plugin_config(config)
    local entity = {
      id = utils.uuid(),
      name = oidc_schema.name,
      config = config
    }

    local entity_to_select, err = plugins_schema:process_auto_fields(entity, "select")
    if err then
      return nil, err
    end

    return entity_to_select
  end
end



describe(PLUGIN_NAME .. ": (schema)", function()
  local bp

  lazy_setup(function()
    bp = helpers.get_db_utils()

    bp.consumers:insert {
      username = "anonymous-name",
    }
  end)

  lazy_teardown(function()
    -- placeholder
  end)

  it("allows to configure plugin with issuer url", function()
    local ok, err = validate({
        issuer = "https://accounts.google.test/.well-known/openid-configuration",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  it("does not allow configure plugin without issuer url", function()
    local ok, err = validate({
      })
    assert.is_same({
        config = {
          issuer = 'required field missing'
        }
      }, err)
    assert.is_falsy(ok)
  end)

  it("redis cluster nodes accepts ips or hostnames", function()
    local ok, err = validate({
      issuer = "https://accounts.google.test/.well-known/openid-configuration",
      session_redis_cluster_nodes = {
        {
          ip = "redis-node-1",
          port = 6379,
        },
        {
          ip = "redis-node-2",
          port = 6380,
        },
        {
          ip = "127.0.0.1",
          port = 6381,
        },
      },
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  it("redis cluster nodes rejects bad ports", function()
    local ok, err = validate({
      issuer = "https://accounts.google.test/.well-known/openid-configuration",
      session_redis_cluster_nodes = {
        {
          ip = "redis-node-1",
          port = "6379",
        },
        {
          ip = "redis-node-2",
          port = 6380,
        },
      },
    })
    assert.is_same(
    { port = "expected an integer" },
    err.config.session_redis_cluster_nodes[1]
    )
    assert.is_falsy(ok)
  end)


  it("accepts anonymous config with uuid #FTI-3340", function()
    local uuid = utils.uuid()
    local ok, err = validate({
      issuer = "https://accounts.google.test/.well-known/openid-configuration",
      anonymous = uuid,
    })

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts anonymous config with existing username #FTI-3340 #ONLY", function()
    local ok, err = validate({
      issuer = "https://accounts.google.test/.well-known/openid-configuration",
      anonymous = "anonymous-name",
    })

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts anonymous config with arbitrary string #FTI-3340", function()
    local ok, err = validate({
      issuer = "https://accounts.google.test/.well-known/openid-configuration",
      anonymous = "nobody",
    })

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  for _, pop_mtls in ipairs({ "strict", "optional", "off" }) do
    for _, auth_methods_validation in ipairs({ true, false }) do
      describe("mTLS proof_of_possession_mtls restrictions with proof_of_possession_auth_methods_validation=" .. tostring(auth_methods_validation), function ()
        for _, plugin_on in ipairs{false, true} do
          it("mtls plugin dependence check with plugin="..tostring(plugin_on), function()
            if plugin_on then
              helpers.test_conf.loaded_plugins["mtls-auth"] = true
              helpers.test_conf.loaded_plugins["tls-handshake-modifier"] = true
            else
              helpers.test_conf.loaded_plugins["mtls-auth"] = false
              helpers.test_conf.loaded_plugins["tls-handshake-modifier"] = false
            end

            local _, err = validate({
              issuer = "https://accounts.google.test/.well-known/openid-configuration",
              proof_of_possession_auth_methods_validation = auth_methods_validation,
              proof_of_possession_mtls = "strict",
              auth_methods = {
                "bearer",
                "introspection"
              },
            })

            if plugin_on then
              assert.is_nil(err)
            else
              assert.same(err, {
                config = "mTLS-proof-of-possession requires client certificate authentication. 'tls-handshake-modifier' or 'mtls-auth' plugin could be used for this purpose."
              })
            end
          end)
        end

        describe("other checks", function ()
          lazy_setup(function ()
            helpers.test_conf.loaded_plugins["mtls-auth"] = true
            helpers.test_conf.loaded_plugins["tls-handshake-modifier"] = true
          end)

          lazy_teardown(function ()
            helpers.test_conf.loaded_plugins["mtls-auth"] = false
            helpers.test_conf.loaded_plugins["tls-handshake-modifier"] = false
          end)

          it("auth_methods check", function()
            assert(validate({
              issuer = "https://accounts.google.test/.well-known/openid-configuration",
              proof_of_possession_auth_methods_validation = auth_methods_validation,
              proof_of_possession_mtls = pop_mtls,
              auth_methods = {
                "bearer",
                "introspection",
                "session",
              },
            }))

            assert(validate({
              issuer = "https://accounts.google.test/.well-known/openid-configuration",
              proof_of_possession_auth_methods_validation = auth_methods_validation,
              proof_of_possession_mtls = pop_mtls,
              auth_methods = {
                "bearer",
              },
            }))

            local ok, err = validate({
              issuer = "https://accounts.google.test/.well-known/openid-configuration",
              proof_of_possession_auth_methods_validation = auth_methods_validation,
              proof_of_possession_mtls = pop_mtls,
              auth_methods = {
                "client_credentials",
                "bearer",
              },
            })

            if auth_methods_validation and (pop_mtls == "strict" or pop_mtls == "optional") then
              assert.is_falsy(ok)

              assert.same(err, {
                config = "mTLS-proof-of-possession only supports 'bearer', 'introspection', 'session' auth methods when proof_of_possession_auth_methods_validation is set to true."
              })
            else
              assert.is_truthy(ok)
            end

            ok, err = validate({
              issuer = "https://accounts.google.test/.well-known/openid-configuration",
              proof_of_possession_auth_methods_validation = auth_methods_validation,
              proof_of_possession_mtls = pop_mtls,
            })

            if auth_methods_validation and (pop_mtls == "strict" or pop_mtls == "optional") then
              assert.is_falsy(ok)

              assert.same(err, {
                config = "mTLS-proof-of-possession only supports 'bearer', 'introspection', 'session' auth methods when proof_of_possession_auth_methods_validation is set to true."
              })
            else
              assert.is_truthy(ok)
            end

          end)
        end)
      end)
    end
  end

  describe("referenceable fields", function()
    lazy_setup(function()
      _G.kong = {
        log   = require "kong.pdk.log".new(),
        vault = require "kong.pdk.vault".new(),
      }
      helpers.setenv("TEST_SCOPE_FOO", "foo")
      helpers.setenv("TEST_SCOPE_BAR", "bar")
      helpers.setenv("TEST_LOGIN_URI", "http://login.test")
      helpers.setenv("TEST_LOGOUT_URI", "http://logout.test")
    end)
    lazy_teardown(function()
      helpers.unsetenv("TEST_SCOPE_FOO")
      helpers.unsetenv("TEST_SCOPE_BAR")
      helpers.unsetenv("TEST_LOGIN_URI")
      helpers.unsetenv("TEST_LOGOUT_URI")
      _G.kong = nil
    end)

    it("scopes", function()
      local res, err = process_plugin_config({
        issuer = "https://accounts.google.test/.well-known/openid-configuration",
        scopes = { "{vault://env/test_scope_foo}", "{vault://env/test_scope_bar}"},
      })
      assert.is_nil(err)
      assert.same({ "foo", "bar" }, res.config.scopes)
    end)

    it("login_redirect_uri/logout_redirect_uri", function()
      local res, err = process_plugin_config({
        issuer = "https://accounts.google.test/.well-known/openid-configuration",
        login_redirect_uri = { "{vault://env/test_login_uri}" },
        logout_redirect_uri = { "{vault://env/test_logout_uri}" },
      })
      assert.is_nil(err)
      assert.same({ "http://login.test" }, res.config.login_redirect_uri)
      assert.same({ "http://logout.test" }, res.config.logout_redirect_uri)
    end)

  end)

end)
