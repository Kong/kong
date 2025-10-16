local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

describe("hmac-auth: (vault integration)", function()
  local get

  before_each(function()
    local conf = assert(conf_loader(nil, {
      vaults = "bundled",
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf)

    get = _G.kong.vault.get
  end)

  describe("hmac-auth credentials vault reference resolution", function()
    it("should dereference vault value for secret field", function()
      local env_name = "HMAC_SECRET"
      local env_value = "hmac_secret_key_123"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/hmac_secret}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should dereference vault value for username field", function()
      local env_name = "HMAC_USERNAME"
      local env_value = "hmac_user_123"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/hmac_username}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should handle vault reference with different environment variable names", function()
      local secret_env = "HMAC_PRIVATE_SECRET"
      local username_env = "HMAC_USER_ID" 
      local secret_value = "private_hmac_456"
      local username_value = "hmac_consumer"

      finally(function()
        helpers.unsetenv(secret_env)
        helpers.unsetenv(username_env)
      end)

      helpers.setenv(secret_env, secret_value)
      helpers.setenv(username_env, username_value)

      local secret_res, secret_err = get("{vault://env/hmac_private_secret}")
      local username_res, username_err = get("{vault://env/hmac_user_id}")
      
      assert.is_nil(secret_err)
      assert.is_nil(username_err)
      assert.equal(secret_value, secret_res)
      assert.equal(username_value, username_res)
    end)

    it("should handle vault reference with JSON secrets containing HMAC credentials", function()
      local env_name = "HMAC_CREDENTIALS"
      local env_value = '{"username": "hmac_user", "secret": "hmac_secret_789"}'

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local username_res, username_err = get("{vault://env/hmac_credentials/username}")
      local secret_res, secret_err = get("{vault://env/hmac_credentials/secret}")
      
      assert.is_nil(username_err)
      assert.is_nil(secret_err)
      assert.equal("hmac_user", username_res)
      assert.equal("hmac_secret_789", secret_res)
    end)

    it("should fail gracefully when HMAC environment variables do not exist", function()
      helpers.unsetenv("NON_EXISTENT_HMAC_SECRET")
      helpers.unsetenv("NON_EXISTENT_HMAC_USERNAME")
      
      local secret_res, secret_err = get("{vault://env/non_existent_hmac_secret}")
      local username_res, username_err = get("{vault://env/non_existent_hmac_username}")
      
      assert.matches("could not get value from external vault", secret_err)
      assert.matches("could not get value from external vault", username_err)
      assert.is_nil(secret_res)
      assert.is_nil(username_res)
    end)

    it("should handle vault reference with prefix for HMAC credentials", function()
      local secret_env = "HMAC_SECRET"
      local username_env = "HMAC_USERNAME"
      local secret_value = "prefixed_hmac_secret"
      local username_value = "prefixed_hmac_user"

      finally(function()
        helpers.unsetenv(secret_env)
        helpers.unsetenv(username_env)
      end)

      helpers.setenv(secret_env, secret_value)
      helpers.setenv(username_env, username_value)

      local secret_res, secret_err = get("{vault://env/secret?prefix=hmac_}")
      local username_res, username_err = get("{vault://env/username?prefix=hmac_}")
      
      assert.is_nil(secret_err)
      assert.is_nil(username_err)
      assert.equal(secret_value, secret_res)
      assert.equal(username_value, username_res)
    end)

    it("should work with empty HMAC environment variable values", function()
      local secret_env = "EMPTY_HMAC_SECRET"
      local username_env = "EMPTY_HMAC_USERNAME"

      finally(function()
        helpers.unsetenv(secret_env)
        helpers.unsetenv(username_env)
      end)

      helpers.setenv(secret_env, "")
      helpers.setenv(username_env, "")

      local secret_res, secret_err = get("{vault://env/empty_hmac_secret}")
      local username_res, username_err = get("{vault://env/empty_hmac_username}")
      
      assert.is_nil(secret_err)
      assert.is_nil(username_err)
      assert.equal("", secret_res)
      assert.equal("", username_res)
    end)
  end)

  describe("edge cases and validation", function()
    it("should handle malformed vault references gracefully", function()
      local malformed_refs = {
        "{vault://invalid/format",
        "vault://env/missing_braces}",
        "{vault://env/}",
        "{vault://env}",
        "{vault://}",
      }

      for _, ref in ipairs(malformed_refs) do
        local res, err = get(ref)
        if res then
          assert.equal(ref, res, "Malformed reference should be returned unchanged: " .. ref)
        else
          assert.is_string(err, "Should have error message for malformed reference: " .. ref)
        end
      end
    end)

    it("should handle case sensitivity correctly", function()
      finally(function()
        helpers.unsetenv("Test_HMAC_Secret")
        helpers.unsetenv("Test_HMAC_User")
      end)

      helpers.setenv("Test_HMAC_Secret", "case_sensitive_hmac_secret")
      helpers.setenv("Test_HMAC_User", "case_sensitive_hmac_user")

      local secret_res, secret_err = get("{vault://env/test_hmac_secret}")
      local user_res, user_err = get("{vault://env/test_hmac_user}")
      
      assert.matches("could not get value from external vault", secret_err)
      assert.matches("could not get value from external vault", user_err)
      assert.is_nil(secret_res)
      assert.is_nil(user_res)
    end)

    it("should work with special characters in HMAC environment variable names", function()
      local secret_env = "HMAC_SECRET_123"
      local username_env = "HMAC_USER_456"
      local secret_value = "special_hmac_secret"
      local username_value = "special_hmac_user"

      finally(function()
        helpers.unsetenv(secret_env)
        helpers.unsetenv(username_env)
      end)

      helpers.setenv(secret_env, secret_value)
      helpers.setenv(username_env, username_value)

      local secret_res, secret_err = get("{vault://env/hmac_secret_123}")
      local username_res, username_err = get("{vault://env/hmac_user_456}")
      
      assert.is_nil(secret_err)
      assert.is_nil(username_err)
      assert.equal(secret_value, secret_res)
      assert.equal(username_value, username_res)
    end)
  end)

  describe("integration with hmac-auth plugin", function()
    it("should demonstrate vault usage in HMAC-Auth context", function()
      local secret_env = "HMAC_INTEGRATION_SECRET"
      local username_env = "HMAC_INTEGRATION_USERNAME"
      
      finally(function()
        helpers.unsetenv(secret_env)
        helpers.unsetenv(username_env)
      end)

      helpers.setenv(secret_env, "secure_hmac_secret_123")
      helpers.setenv(username_env, "secure_hmac_username")

      local resolved_secret, secret_err = get("{vault://env/hmac_integration_secret}")
      local resolved_username, username_err = get("{vault://env/hmac_integration_username}")

      assert.is_nil(secret_err)
      assert.is_nil(username_err)
      assert.equal("secure_hmac_secret_123", resolved_secret)
      assert.equal("secure_hmac_username", resolved_username)

      -- In actual usage, these resolved values would be used to:
      -- 1. Create HMAC-Auth credentials with resolved username and secret
      -- 2. Validate HMAC signatures using the resolved secret
      -- 3. The secret is used to generate HMAC signatures for request validation
      -- 4. The username identifies the consumer making the request
    end)

    it("should handle multiple HMAC credential scenarios", function()
      finally(function()
        helpers.unsetenv("HMAC_ADMIN_SECRET")
        helpers.unsetenv("HMAC_ADMIN_USER")
        helpers.unsetenv("HMAC_API_SECRET")
        helpers.unsetenv("HMAC_API_USER")
      end)

      -- Admin credentials
      helpers.setenv("HMAC_ADMIN_SECRET", "admin_hmac_secret")
      helpers.setenv("HMAC_ADMIN_USER", "admin_user")
      
      -- API credentials 
      helpers.setenv("HMAC_API_SECRET", "api_hmac_secret")
      helpers.setenv("HMAC_API_USER", "api_user")

      local admin_secret_res, admin_secret_err = get("{vault://env/hmac_admin_secret}")
      local admin_user_res, admin_user_err = get("{vault://env/hmac_admin_user}")
      local api_secret_res, api_secret_err = get("{vault://env/hmac_api_secret}")
      local api_user_res, api_user_err = get("{vault://env/hmac_api_user}")
      
      assert.is_nil(admin_secret_err)
      assert.is_nil(admin_user_err)
      assert.is_nil(api_secret_err)
      assert.is_nil(api_user_err)
      
      assert.equal("admin_hmac_secret", admin_secret_res)
      assert.equal("admin_user", admin_user_res)
      assert.equal("api_hmac_secret", api_secret_res)
      assert.equal("api_user", api_user_res)
    end)
  end)
end)