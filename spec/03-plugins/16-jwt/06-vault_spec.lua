local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

local PLUGIN_NAME = "jwt"

describe(PLUGIN_NAME .. ": (vault integration)", function()
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

  it("should dereference vault value for secret field", function()
    local env_name = "JWT_SECRET"
    local env_value = "jwt_secret_key_123"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/jwt_secret}")
    assert.is_nil(err)
    assert.equal(env_value, res)
  end)

  it("should handle vault reference with different environment variable name", function()
    local env_name = "JWT_PRIVATE_KEY"
    local env_value = "private_key_456"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/jwt_private_key}")
    assert.is_nil(err)
    assert.equal(env_value, res)
  end)

  it("should handle vault reference with JSON secret containing JWT keys", function()
    local env_name = "JWT_KEYS"
    local env_value = '{"secret": "jwt_secret_789", "algorithm": "HS256"}'

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/jwt_keys/secret}")
    assert.is_nil(err)
    assert.equal("jwt_secret_789", res)
  end)

  it("should fail gracefully when JWT secret environment variable does not exist", function()
    helpers.unsetenv("NON_EXISTENT_JWT_SECRET")

    local res, err = get("{vault://env/non_existent_jwt_secret}")
    assert.matches("could not get value from external vault", err)
    assert.is_nil(res)
  end)

  it("should handle vault reference with prefix for JWT secrets", function()
    local env_name = "JWT_SECRET"
    local env_value = "prefixed_jwt_secret"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/secret?prefix=jwt_}")
    assert.is_nil(err)
    assert.equal(env_value, res)
  end)

  it("should work with empty JWT secret environment variable value", function()
    local env_name = "EMPTY_JWT_SECRET"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, "")

    local res, err = get("{vault://env/empty_jwt_secret}")
    assert.is_nil(err)
    assert.equal("", res)
  end)

  it("should handle RSA public key from environment variable", function()
    local env_name = "JWT_RSA_PUBLIC_KEY"
    local env_value = "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/jwt_rsa_public_key}")
    assert.is_nil(err)
    assert.equal(env_value, res)
  end)

  it("should demonstrate vault usage in JWT context", function()
    local secret_env = "JWT_INTEGRATION_SECRET"
    local key_env = "JWT_INTEGRATION_KEY"

    finally(function()
      helpers.unsetenv(secret_env)
      helpers.unsetenv(key_env)
    end)

    helpers.setenv(secret_env, "secure_jwt_secret_123")
    helpers.setenv(key_env, "jwt_consumer_key")

    local resolved_secret, secret_err = get("{vault://env/jwt_integration_secret}")
    local resolved_key, key_err = get("{vault://env/jwt_integration_key}")

    assert.is_nil(secret_err)
    assert.is_nil(key_err)
    assert.equal("secure_jwt_secret_123", resolved_secret)
    assert.equal("jwt_consumer_key", resolved_key)

    -- In actual usage, these resolved values would be used to:
    -- 1. Create JWT credentials with resolved secret
    -- 2. Validate JWT tokens using the resolved secret
    -- 3. The secret can be used for HS256/HS384/HS512 algorithms
    -- 4. For RSA algorithms, the secret would contain the private/public key
  end)

  it("should handle both symmetric and asymmetric key scenarios", function()
    finally(function()
      helpers.unsetenv("JWT_HMAC_SECRET")
      helpers.unsetenv("JWT_RSA_PRIVATE_KEY")
    end)

    -- Symmetric key scenario (HMAC)
    helpers.setenv("JWT_HMAC_SECRET", "hmac_shared_secret")

    -- Asymmetric key scenario (RSA)
    helpers.setenv("JWT_RSA_PRIVATE_KEY", "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----")

    local hmac_res, hmac_err = get("{vault://env/jwt_hmac_secret}")
    local rsa_res, rsa_err = get("{vault://env/jwt_rsa_private_key}")

    assert.is_nil(hmac_err)
    assert.is_nil(rsa_err)
    assert.equal("hmac_shared_secret", hmac_res)
    assert.equal("-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----", rsa_res)
  end)

  it("should handle case sensitivity correctly", function()
    finally(function()
      helpers.unsetenv("Test_JWT_Secret")
    end)

    helpers.setenv("Test_JWT_Secret", "case_sensitive_jwt_value")

    local res, err = get("{vault://env/test_jwt_secret}")
    assert.matches("could not get value from external vault", err)
    assert.is_nil(res)
  end)

  it("should work with special characters in JWT environment variable names", function()
    local env_name = "JWT_SECRET_123"
    local env_value = "special_jwt_value"

    finally(function()
      helpers.unsetenv(env_name)
    end)

    helpers.setenv(env_name, env_value)

    local res, err = get("{vault://env/jwt_secret_123}")
    assert.is_nil(err)
    assert.equal(env_value, res)
  end)
end)