local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

describe("request-transformer: (vault integration)", function()
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

  describe("request-transformer configuration vault reference resolution", function()
    it("should dereference vault value for header transformation", function()
      local env_name = "REQUEST_HEADER_VALUE"
      local env_value = "X-Custom-Header-Value"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/request_header_value}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should dereference vault value for body transformation", function()
      local env_name = "REQUEST_BODY_VALUE"
      local env_value = "transformed_body_content"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/request_body_value}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should dereference vault value for querystring transformation", function()
      local env_name = "REQUEST_QUERY_VALUE"
      local env_value = "query_param_value_123"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/request_query_value}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should handle vault reference with different transformation types", function()
      local header_env = "ADD_HEADER_VALUE"
      local body_env = "ADD_BODY_PARAM"
      local query_env = "ADD_QUERY_PARAM"
      
      local header_value = "Authorization: Bearer secret_token"
      local body_value = "api_key:secret_api_key_123"
      local query_value = "token:query_token_456"

      finally(function()
        helpers.unsetenv(header_env)
        helpers.unsetenv(body_env)
        helpers.unsetenv(query_env)
      end)

      helpers.setenv(header_env, header_value)
      helpers.setenv(body_env, body_value)
      helpers.setenv(query_env, query_value)

      local header_res, header_err = get("{vault://env/add_header_value}")
      local body_res, body_err = get("{vault://env/add_body_param}")
      local query_res, query_err = get("{vault://env/add_query_param}")
      
      assert.is_nil(header_err)
      assert.is_nil(body_err)
      assert.is_nil(query_err)
      assert.equal(header_value, header_res)
      assert.equal(body_value, body_res)
      assert.equal(query_value, query_res)
    end)

    it("should handle vault reference with JSON configuration", function()
      local env_name = "REQUEST_TRANSFORM_CONFIG"
      local env_value = '{"header": "X-API-Key:secret_key", "body": "auth_token:bearer_token_789"}'

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local header_res, header_err = get("{vault://env/request_transform_config/header}")
      local body_res, body_err = get("{vault://env/request_transform_config/body}")
      
      assert.is_nil(header_err)
      assert.is_nil(body_err)
      assert.equal("X-API-Key:secret_key", header_res)
      assert.equal("auth_token:bearer_token_789", body_res)
    end)

    it("should fail gracefully when transformation environment variables do not exist", function()
      helpers.unsetenv("NON_EXISTENT_HEADER")
      helpers.unsetenv("NON_EXISTENT_BODY")
      helpers.unsetenv("NON_EXISTENT_QUERY")
      
      local header_res, header_err = get("{vault://env/non_existent_header}")
      local body_res, body_err = get("{vault://env/non_existent_body}")
      local query_res, query_err = get("{vault://env/non_existent_query}")
      
      assert.matches("could not get value from external vault", header_err)
      assert.matches("could not get value from external vault", body_err)
      assert.matches("could not get value from external vault", query_err)
      assert.is_nil(header_res)
      assert.is_nil(body_res)
      assert.is_nil(query_res)
    end)

    it("should handle vault reference with prefix for request transformations", function()
      local header_env = "REQ_HEADER_AUTH"
      local body_env = "REQ_BODY_TOKEN"
      local query_env = "REQ_QUERY_KEY"
      
      local header_value = "X-Auth-Token:prefixed_header_token"
      local body_value = "token:prefixed_body_token"
      local query_value = "key:prefixed_query_key"

      finally(function()
        helpers.unsetenv(header_env)
        helpers.unsetenv(body_env)
        helpers.unsetenv(query_env)
      end)

      helpers.setenv(header_env, header_value)
      helpers.setenv(body_env, body_value)
      helpers.setenv(query_env, query_value)

      local header_res, header_err = get("{vault://env/header_auth?prefix=req_}")
      local body_res, body_err = get("{vault://env/body_token?prefix=req_}")
      local query_res, query_err = get("{vault://env/query_key?prefix=req_}")
      
      assert.is_nil(header_err)
      assert.is_nil(body_err)
      assert.is_nil(query_err)
      assert.equal(header_value, header_res)
      assert.equal(body_value, body_res)
      assert.equal(query_value, query_res)
    end)

    it("should work with empty transformation environment variable values", function()
      local header_env = "EMPTY_HEADER_TRANSFORM"
      local body_env = "EMPTY_BODY_TRANSFORM"
      local query_env = "EMPTY_QUERY_TRANSFORM"

      finally(function()
        helpers.unsetenv(header_env)
        helpers.unsetenv(body_env)
        helpers.unsetenv(query_env)
      end)

      helpers.setenv(header_env, "")
      helpers.setenv(body_env, "")
      helpers.setenv(query_env, "")

      local header_res, header_err = get("{vault://env/empty_header_transform}")
      local body_res, body_err = get("{vault://env/empty_body_transform}")
      local query_res, query_err = get("{vault://env/empty_query_transform}")
      
      assert.is_nil(header_err)
      assert.is_nil(body_err)
      assert.is_nil(query_err)
      assert.equal("", header_res)
      assert.equal("", body_res)
      assert.equal("", query_res)
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
        helpers.unsetenv("Test_Transform_Header")
        helpers.unsetenv("Test_Transform_Body")
      end)

      helpers.setenv("Test_Transform_Header", "case_sensitive_header")
      helpers.setenv("Test_Transform_Body", "case_sensitive_body")

      local header_res, header_err = get("{vault://env/test_transform_header}")
      local body_res, body_err = get("{vault://env/test_transform_body}")
      
      assert.matches("could not get value from external vault", header_err)
      assert.matches("could not get value from external vault", body_err)
      assert.is_nil(header_res)
      assert.is_nil(body_res)
    end)

    it("should work with special characters in transformation environment variable names", function()
      local header_env = "TRANSFORM_HEADER_123"
      local body_env = "TRANSFORM_BODY_456"
      local header_value = "X-Special-Header:special_value"
      local body_value = "special_param:special_body_value"

      finally(function()
        helpers.unsetenv(header_env)
        helpers.unsetenv(body_env)
      end)

      helpers.setenv(header_env, header_value)
      helpers.setenv(body_env, body_value)

      local header_res, header_err = get("{vault://env/transform_header_123}")
      local body_res, body_err = get("{vault://env/transform_body_456}")
      
      assert.is_nil(header_err)
      assert.is_nil(body_err)
      assert.equal(header_value, header_res)
      assert.equal(body_value, body_res)
    end)

    it("should handle colon-separated key:value transformation formats", function()
      local env_name = "COLON_TRANSFORM"
      local env_value = "X-Custom-Auth:Bearer secret_token_123"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/colon_transform}")
      assert.is_nil(err)
      assert.equal(env_value, res)
      
      -- Verify the format matches request-transformer expectations
      local key, value = env_value:match("^([^:]+):(.+)$")
      assert.equal("X-Custom-Auth", key)
      assert.equal("Bearer secret_token_123", value)
    end)
  end)

  describe("integration with request-transformer plugin", function()
    it("should demonstrate vault usage in Request-Transformer context", function()
      local add_header_env = "ADD_AUTH_HEADER"
      local add_body_env = "ADD_API_KEY"
      local add_query_env = "ADD_VERSION_PARAM"
      
      finally(function()
        helpers.unsetenv(add_header_env)
        helpers.unsetenv(add_body_env)
        helpers.unsetenv(add_query_env)
      end)

      helpers.setenv(add_header_env, "Authorization:Bearer vault_token_123")
      helpers.setenv(add_body_env, "api_key:vault_api_key_456")
      helpers.setenv(add_query_env, "version:v2")

      local resolved_header, header_err = get("{vault://env/add_auth_header}")
      local resolved_body, body_err = get("{vault://env/add_api_key}")
      local resolved_query, query_err = get("{vault://env/add_version_param}")

      assert.is_nil(header_err)
      assert.is_nil(body_err)
      assert.is_nil(query_err)
      assert.equal("Authorization:Bearer vault_token_123", resolved_header)
      assert.equal("api_key:vault_api_key_456", resolved_body)
      assert.equal("version:v2", resolved_query)

      -- In actual usage, these resolved values would be used in:
      -- config.add.headers = ["{vault://env/add_auth_header}"]
      -- config.add.body = ["{vault://env/add_api_key}"]
      -- config.add.querystring = ["{vault://env/add_version_param}"]
    end)

    it("should handle multiple transformation operations", function()
      finally(function()
        helpers.unsetenv("REPLACE_HEADER")
        helpers.unsetenv("APPEND_HEADER") 
        helpers.unsetenv("REMOVE_HEADER")
        helpers.unsetenv("RENAME_HEADER")
      end)

      -- Different transformation operations
      helpers.setenv("REPLACE_HEADER", "X-Original-Header:X-Replaced-Header")
      helpers.setenv("APPEND_HEADER", "X-Append-Token:appended_token_789")
      helpers.setenv("REMOVE_HEADER", "X-Remove-This")
      helpers.setenv("RENAME_HEADER", "X-Old-Name:X-New-Name")

      local replace_res, replace_err = get("{vault://env/replace_header}")
      local append_res, append_err = get("{vault://env/append_header}")
      local remove_res, remove_err = get("{vault://env/remove_header}")
      local rename_res, rename_err = get("{vault://env/rename_header}")
      
      assert.is_nil(replace_err)
      assert.is_nil(append_err)
      assert.is_nil(remove_err)
      assert.is_nil(rename_err)
      
      assert.equal("X-Original-Header:X-Replaced-Header", replace_res)
      assert.equal("X-Append-Token:appended_token_789", append_res)
      assert.equal("X-Remove-This", remove_res)
      assert.equal("X-Old-Name:X-New-Name", rename_res)

      -- These would be used in configuration like:
      -- config.replace.headers = ["{vault://env/replace_header}"]
      -- config.append.headers = ["{vault://env/append_header}"]  
      -- config.remove.headers = ["{vault://env/remove_header}"]
      -- config.rename.headers = ["{vault://env/rename_header}"]
    end)

    it("should handle template variables in transformations", function()
      finally(function()
        helpers.unsetenv("TEMPLATE_HEADER")
        helpers.unsetenv("TEMPLATE_BODY")
      end)

      -- Template variables that can be used in request-transformer
      helpers.setenv("TEMPLATE_HEADER", "X-Consumer-ID:$(headers.x_consumer_id)")
      helpers.setenv("TEMPLATE_BODY", "upstream_uri:$(upstream_uri)")

      local template_header_res, template_header_err = get("{vault://env/template_header}")
      local template_body_res, template_body_err = get("{vault://env/template_body}")
      
      assert.is_nil(template_header_err)
      assert.is_nil(template_body_err)
      assert.equal("X-Consumer-ID:$(headers.x_consumer_id)", template_header_res)
      assert.equal("upstream_uri:$(upstream_uri)", template_body_res)

      -- These demonstrate how vault can store template expressions
      -- that will be evaluated during request transformation
    end)
  end)
end)