local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

describe("oauth2: (vault integration)", function()
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

  describe("oauth2 credentials vault reference resolution", function()
    it("should dereference vault value for client_secret field", function()
      local env_name = "OAUTH2_CLIENT_SECRET"
      local env_value = "oauth2_client_secret_123"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/oauth2_client_secret}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should dereference vault value for client_id field", function()
      local env_name = "OAUTH2_CLIENT_ID"
      local env_value = "oauth2_client_id_456"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/oauth2_client_id}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should handle vault reference with different environment variable names", function()
      local client_id_env = "OAUTH2_APP_ID"
      local client_secret_env = "OAUTH2_APP_SECRET" 
      local client_id_value = "app_id_789"
      local client_secret_value = "app_secret_012"

      finally(function()
        helpers.unsetenv(client_id_env)
        helpers.unsetenv(client_secret_env)
      end)

      helpers.setenv(client_id_env, client_id_value)
      helpers.setenv(client_secret_env, client_secret_value)

      local client_id_res, client_id_err = get("{vault://env/oauth2_app_id}")
      local client_secret_res, client_secret_err = get("{vault://env/oauth2_app_secret}")
      
      assert.is_nil(client_id_err)
      assert.is_nil(client_secret_err)
      assert.equal(client_id_value, client_id_res)
      assert.equal(client_secret_value, client_secret_res)
    end)

    it("should handle vault reference with JSON secrets containing OAuth2 credentials", function()
      local env_name = "OAUTH2_CREDENTIALS"
      local env_value = '{"client_id": "oauth2_client_123", "client_secret": "oauth2_secret_456"}'

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local client_id_res, client_id_err = get("{vault://env/oauth2_credentials/client_id}")
      local client_secret_res, client_secret_err = get("{vault://env/oauth2_credentials/client_secret}")
      
      assert.is_nil(client_id_err)
      assert.is_nil(client_secret_err)
      assert.equal("oauth2_client_123", client_id_res)
      assert.equal("oauth2_secret_456", client_secret_res)
    end)

    it("should fail gracefully when OAuth2 environment variables do not exist", function()
      helpers.unsetenv("NON_EXISTENT_CLIENT_ID")
      helpers.unsetenv("NON_EXISTENT_CLIENT_SECRET")
      
      local client_id_res, client_id_err = get("{vault://env/non_existent_client_id}")
      local client_secret_res, client_secret_err = get("{vault://env/non_existent_client_secret}")
      
      assert.matches("could not get value from external vault", client_id_err)
      assert.matches("could not get value from external vault", client_secret_err)
      assert.is_nil(client_id_res)
      assert.is_nil(client_secret_res)
    end)

    it("should handle vault reference with prefix for OAuth2 credentials", function()
      local client_id_env = "OAUTH2_CLIENT_ID"
      local client_secret_env = "OAUTH2_CLIENT_SECRET"
      local client_id_value = "prefixed_oauth2_id"
      local client_secret_value = "prefixed_oauth2_secret"

      finally(function()
        helpers.unsetenv(client_id_env)
        helpers.unsetenv(client_secret_env)
      end)

      helpers.setenv(client_id_env, client_id_value)
      helpers.setenv(client_secret_env, client_secret_value)

      local client_id_res, client_id_err = get("{vault://env/client_id?prefix=oauth2_}")
      local client_secret_res, client_secret_err = get("{vault://env/client_secret?prefix=oauth2_}")
      
      assert.is_nil(client_id_err)
      assert.is_nil(client_secret_err)
      assert.equal(client_id_value, client_id_res)
      assert.equal(client_secret_value, client_secret_res)
    end)

    it("should work with empty OAuth2 environment variable values", function()
      local client_id_env = "EMPTY_OAUTH2_CLIENT_ID"
      local client_secret_env = "EMPTY_OAUTH2_CLIENT_SECRET"

      finally(function()
        helpers.unsetenv(client_id_env)
        helpers.unsetenv(client_secret_env)
      end)

      helpers.setenv(client_id_env, "")
      helpers.setenv(client_secret_env, "")

      local client_id_res, client_id_err = get("{vault://env/empty_oauth2_client_id}")
      local client_secret_res, client_secret_err = get("{vault://env/empty_oauth2_client_secret}")
      
      assert.is_nil(client_id_err)
      assert.is_nil(client_secret_err)
      assert.equal("", client_id_res)
      assert.equal("", client_secret_res)
    end)

    it("should handle hash_secret boolean field from environment", function()
      local env_name = "OAUTH2_HASH_SECRET"
      local env_value = "true"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/oauth2_hash_secret}")
      assert.is_nil(err)
      assert.equal(env_value, res)
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
        helpers.unsetenv("Test_OAuth2_Client_Id")
        helpers.unsetenv("Test_OAuth2_Client_Secret")
      end)

      helpers.setenv("Test_OAuth2_Client_Id", "case_sensitive_client_id")
      helpers.setenv("Test_OAuth2_Client_Secret", "case_sensitive_client_secret")

      local client_id_res, client_id_err = get("{vault://env/test_oauth2_client_id}")
      local client_secret_res, client_secret_err = get("{vault://env/test_oauth2_client_secret}")
      
      assert.matches("could not get value from external vault", client_id_err)
      assert.matches("could not get value from external vault", client_secret_err)
      assert.is_nil(client_id_res)
      assert.is_nil(client_secret_res)
    end)

    it("should work with special characters in OAuth2 environment variable names", function()
      local client_id_env = "OAUTH2_CLIENT_ID_123"
      local client_secret_env = "OAUTH2_CLIENT_SECRET_456"
      local client_id_value = "special_oauth2_client_id"
      local client_secret_value = "special_oauth2_client_secret"

      finally(function()
        helpers.unsetenv(client_id_env)
        helpers.unsetenv(client_secret_env)
      end)

      helpers.setenv(client_id_env, client_id_value)
      helpers.setenv(client_secret_env, client_secret_value)

      local client_id_res, client_id_err = get("{vault://env/oauth2_client_id_123}")
      local client_secret_res, client_secret_err = get("{vault://env/oauth2_client_secret_456}")
      
      assert.is_nil(client_id_err)
      assert.is_nil(client_secret_err)
      assert.equal(client_id_value, client_id_res)
      assert.equal(client_secret_value, client_secret_res)
    end)
  end)

  describe("integration with oauth2 plugin", function()
    it("should demonstrate vault usage in OAuth2 context", function()
      local client_id_env = "OAUTH2_INTEGRATION_CLIENT_ID"
      local client_secret_env = "OAUTH2_INTEGRATION_CLIENT_SECRET"
      
      finally(function()
        helpers.unsetenv(client_id_env)
        helpers.unsetenv(client_secret_env)
      end)

      helpers.setenv(client_id_env, "secure_oauth2_client_id")
      helpers.setenv(client_secret_env, "secure_oauth2_client_secret")

      local resolved_client_id, client_id_err = get("{vault://env/oauth2_integration_client_id}")
      local resolved_client_secret, client_secret_err = get("{vault://env/oauth2_integration_client_secret}")

      assert.is_nil(client_id_err)
      assert.is_nil(client_secret_err)
      assert.equal("secure_oauth2_client_id", resolved_client_id)
      assert.equal("secure_oauth2_client_secret", resolved_client_secret)

      -- In actual usage, these resolved values would be used to:
      -- 1. Create OAuth2 application credentials with resolved client_id and client_secret
      -- 2. Validate OAuth2 authorization requests using the resolved credentials
      -- 3. The client_secret is used to authenticate the application during token exchange
      -- 4. The client_id identifies the OAuth2 application making the request
    end)

    it("should handle multiple OAuth2 application scenarios", function()
      finally(function()
        helpers.unsetenv("OAUTH2_WEB_CLIENT_ID")
        helpers.unsetenv("OAUTH2_WEB_CLIENT_SECRET")
        helpers.unsetenv("OAUTH2_MOBILE_CLIENT_ID")
        helpers.unsetenv("OAUTH2_MOBILE_CLIENT_SECRET")
      end)

      -- Web application credentials
      helpers.setenv("OAUTH2_WEB_CLIENT_ID", "web_app_client_id")
      helpers.setenv("OAUTH2_WEB_CLIENT_SECRET", "web_app_client_secret")
      
      -- Mobile application credentials 
      helpers.setenv("OAUTH2_MOBILE_CLIENT_ID", "mobile_app_client_id")
      helpers.setenv("OAUTH2_MOBILE_CLIENT_SECRET", "mobile_app_client_secret")

      local web_id_res, web_id_err = get("{vault://env/oauth2_web_client_id}")
      local web_secret_res, web_secret_err = get("{vault://env/oauth2_web_client_secret}")
      local mobile_id_res, mobile_id_err = get("{vault://env/oauth2_mobile_client_id}")
      local mobile_secret_res, mobile_secret_err = get("{vault://env/oauth2_mobile_client_secret}")
      
      assert.is_nil(web_id_err)
      assert.is_nil(web_secret_err)
      assert.is_nil(mobile_id_err)
      assert.is_nil(mobile_secret_err)
      
      assert.equal("web_app_client_id", web_id_res)
      assert.equal("web_app_client_secret", web_secret_res)
      assert.equal("mobile_app_client_id", mobile_id_res)
      assert.equal("mobile_app_client_secret", mobile_secret_res)
    end)

    it("should handle OAuth2 configuration flags", function()
      finally(function()
        helpers.unsetenv("OAUTH2_INTEGRATION_HASH_SECRET")
      end)

      helpers.setenv("OAUTH2_INTEGRATION_HASH_SECRET", "false")

      local hash_secret_res, hash_secret_err = get("{vault://env/oauth2_integration_hash_secret}")
      
      assert.is_nil(hash_secret_err)
      assert.equal("false", hash_secret_res)

      -- In actual usage:
      -- - hash_secret=true: client_secret will be hashed before storage
      -- - hash_secret=false: client_secret will be stored as plaintext
      -- The vault reference resolves the boolean value as string
    end)
  end)
end)