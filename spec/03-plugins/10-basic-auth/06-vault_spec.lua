local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

local PLUGIN_NAME = "basic-auth"

describe(PLUGIN_NAME .. ": (schema-vault)", function()
  local plugins_schema = assert(Entity.new(plugins_schema_def))

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      vaults = "bundled",
      plugins = "bundled",
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf)

    local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")
    assert(plugins_schema:new_subschema(PLUGIN_NAME, plugin_schema))
  end)


  it("should handle vault reference with different environment variable name", function()
    local env_name = "BASIC_AUTH_SECRET"
    local env_value = "another_secret_456"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/basic_auth_secret}")
    assert.is_nil(err)
    assert.equal(env_value, res)
  end)

  it("should handle vault reference with JSON secret", function()
    local env_name = "TEST_JSON_SECRETS"
    local env_value = '{"username": "json_user", "password": "db_secret_789"}'

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/test_json_secrets/password}")
    assert.is_nil(err)
    assert.equal("db_secret_789", res)
  end)

  it("should fail gracefully when environment variable does not exist", function()
    helpers.unsetenv("NON_EXISTENT_VAR")

    local res, err = get("{vault://env/non_existent_var}")
    assert.matches("could not get value from external vault", err)
    assert.is_nil(res)
  end)

  it("should handle vault reference with prefix", function()
    local env_name = "TEST_PASSWORD"
    local env_value = "prefixed_secret"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/password?prefix=test_}")
    assert.is_nil(err)
    assert.equal(env_value, res)
  end)

  it("should work with empty environment variable value", function()
    local env_name = "EMPTY_PASSWORD"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, "")

    local res, err = get("{vault://env/empty_password}")
    assert.is_nil(err)
    assert.equal("", res)
  end)

  it("should handle both username and password as vault references", function()
    finally(function()
      helpers.unsetenv("AUTH_USERNAME")
      helpers.unsetenv("AUTH_PASSWORD")
    end)

    helpers.setenv("AUTH_USERNAME", "vault_user_both")
    helpers.setenv("AUTH_PASSWORD", "vault_pass_both")

    local username_res, username_err = get("{vault://env/auth_username}")
    local password_res, password_err = get("{vault://env/auth_password}")

    assert.is_nil(username_err)
    assert.is_nil(password_err)
    assert.equal("vault_user_both", username_res)
    assert.equal("vault_pass_both", password_res)
  end)

  it("should handle malformed vault references gracefully", function()
    -- Test various malformed vault references
    local malformed_refs = {
      "{vault://invalid/format",
      "vault://env/missing_braces}",
      "{vault://env/}",
      "{vault://env}",
      "{vault://}",
    }

    for _, ref in ipairs(malformed_refs) do
      local res, err = get(ref)
      -- Should either return nil with error, or return the original string unchanged
      if res then
        assert.equal(ref, res, "Malformed reference should be returned unchanged: " .. ref)
      else
        assert.is_string(err, "Should have error message for malformed reference: " .. ref)
      end
    end
  end)

  it("should demonstrate vault usage in basic-auth context", function()
    local password_env = "BASIC_AUTH_PASSWORD"
    local username_env = "BASIC_AUTH_USERNAME"

    finally(function()
      helpers.unsetenv(password_env)
      helpers.unsetenv(username_env)
    end)

    helpers.setenv(password_env, "secure_password_123")
    helpers.setenv(username_env, "secure_username")

    -- Simulate how basic-auth would resolve vault references
    local resolved_password, pass_err = get("{vault://env/basic_auth_password}")
    local resolved_username, user_err = get("{vault://env/basic_auth_username}")

    assert.is_nil(pass_err)
    assert.is_nil(user_err)
    assert.equal("secure_password_123", resolved_password)
    assert.equal("secure_username", resolved_username)
  end)
end)

