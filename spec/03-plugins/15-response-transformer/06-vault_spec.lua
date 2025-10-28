local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

describe("response-transformer: (vault integration)", function()
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

  describe("response-transformer configuration vault reference resolution", function()
    it("should dereference vault value for header transformation", function()
      local env_name = "RESPONSE_HEADER_VALUE"
      local env_value = "X-Custom-Response-Header-Value"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/response_header_value}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should dereference vault value for JSON response transformation", function()
      local env_name = "RESPONSE_JSON_VALUE"
      local env_value = "transformed_json_field"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/response_json_value}")
      assert.is_nil(err)
      assert.equal(env_value, res)
    end)

    it("should handle vault reference with different transformation types", function()
      local header_env = "ADD_RESPONSE_HEADER"
      local json_env = "ADD_RESPONSE_JSON"
      
      local header_value = "X-API-Version:2.0"
      local json_value = "api_response_status:success"

      finally(function()
        helpers.unsetenv(header_env)
        helpers.unsetenv(json_env)
      end)

      helpers.setenv(header_env, header_value)
      helpers.setenv(json_env, json_value)

      local header_res, header_err = get("{vault://env/add_response_header}")
      local json_res, json_err = get("{vault://env/add_response_json}")
      
      assert.is_nil(header_err)
      assert.is_nil(json_err)
      assert.equal(header_value, header_res)
      assert.equal(json_value, json_res)
    end)

    it("should handle vault reference with JSON configuration", function()
      local env_name = "RESPONSE_TRANSFORM_CONFIG"
      local env_value = '{"header": "X-Response-ID:response_id_123", "json": "metadata:response_metadata"}'

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local header_res, header_err = get("{vault://env/response_transform_config/header}")
      local json_res, json_err = get("{vault://env/response_transform_config/json}")
      
      assert.is_nil(header_err)
      assert.is_nil(json_err)
      assert.equal("X-Response-ID:response_id_123", header_res)
      assert.equal("metadata:response_metadata", json_res)
    end)

    it("should fail gracefully when response transformation environment variables do not exist", function()
      helpers.unsetenv("NON_EXISTENT_RESPONSE_HEADER")
      helpers.unsetenv("NON_EXISTENT_RESPONSE_JSON")
      
      local header_res, header_err = get("{vault://env/non_existent_response_header}")
      local json_res, json_err = get("{vault://env/non_existent_response_json}")
      
      assert.matches("could not get value from external vault", header_err)
      assert.matches("could not get value from external vault", json_err)
      assert.is_nil(header_res)
      assert.is_nil(json_res)
    end)

    it("should handle vault reference with prefix for response transformations", function()
      local header_env = "RESP_HEADER_CORS"
      local json_env = "RESP_JSON_STATUS"
      
      local header_value = "Access-Control-Allow-Origin:*"
      local json_value = "response_code:200"

      finally(function()
        helpers.unsetenv(header_env)
        helpers.unsetenv(json_env)
      end)

      helpers.setenv(header_env, header_value)
      helpers.setenv(json_env, json_value)

      local header_res, header_err = get("{vault://env/header_cors?prefix=resp_}")
      local json_res, json_err = get("{vault://env/json_status?prefix=resp_}")
      
      assert.is_nil(header_err)
      assert.is_nil(json_err)
      assert.equal(header_value, header_res)
      assert.equal(json_value, json_res)
    end)

    it("should work with empty response transformation environment variable values", function()
      local header_env = "EMPTY_RESPONSE_HEADER"
      local json_env = "EMPTY_RESPONSE_JSON"

      finally(function()
        helpers.unsetenv(header_env)
        helpers.unsetenv(json_env)
      end)

      helpers.setenv(header_env, "")
      helpers.setenv(json_env, "")

      local header_res, header_err = get("{vault://env/empty_response_header}")
      local json_res, json_err = get("{vault://env/empty_response_json}")
      
      assert.is_nil(header_err)
      assert.is_nil(json_err)
      assert.equal("", header_res)
      assert.equal("", json_res)
    end)

    it("should handle security headers from environment variables", function()
      local security_env = "SECURITY_HEADERS"
      local security_value = "X-Frame-Options:DENY"

      finally(function()
        helpers.unsetenv(security_env)
      end)

      helpers.setenv(security_env, security_value)

      local res, err = get("{vault://env/security_headers}")
      assert.is_nil(err)
      assert.equal(security_value, res)
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
        helpers.unsetenv("Test_Response_Header")
        helpers.unsetenv("Test_Response_JSON")
      end)

      helpers.setenv("Test_Response_Header", "case_sensitive_header")
      helpers.setenv("Test_Response_JSON", "case_sensitive_json")

      local header_res, header_err = get("{vault://env/test_response_header}")
      local json_res, json_err = get("{vault://env/test_response_json}")
      
      assert.matches("could not get value from external vault", header_err)
      assert.matches("could not get value from external vault", json_err)
      assert.is_nil(header_res)
      assert.is_nil(json_res)
    end)

    it("should work with special characters in response transformation environment variable names", function()
      local header_env = "RESPONSE_HEADER_123"
      local json_env = "RESPONSE_JSON_456"
      local header_value = "X-Special-Response:special_response_value"
      local json_value = "special_field:special_json_value"

      finally(function()
        helpers.unsetenv(header_env)
        helpers.unsetenv(json_env)
      end)

      helpers.setenv(header_env, header_value)
      helpers.setenv(json_env, json_value)

      local header_res, header_err = get("{vault://env/response_header_123}")
      local json_res, json_err = get("{vault://env/response_json_456}")
      
      assert.is_nil(header_err)
      assert.is_nil(json_err)
      assert.equal(header_value, header_res)
      assert.equal(json_value, json_res)
    end)

    it("should handle colon-separated key:value transformation formats", function()
      local env_name = "COLON_RESPONSE_TRANSFORM"
      local env_value = "Cache-Control:no-cache, no-store, must-revalidate"

      finally(function()
        helpers.unsetenv(env_name)
      end)

      helpers.setenv(env_name, env_value)

      local res, err = get("{vault://env/colon_response_transform}")
      assert.is_nil(err)
      assert.equal(env_value, res)
      
      -- Verify the format matches response-transformer expectations
      local key, value = env_value:match("^([^:]+):(.+)$")
      assert.equal("Cache-Control", key)
      assert.equal("no-cache, no-store, must-revalidate", value)
    end)
  end)

  describe("integration with response-transformer plugin", function()
    it("should demonstrate vault usage in Response-Transformer context", function()
      local add_header_env = "ADD_CORS_HEADER"
      local add_json_env = "ADD_METADATA"
      
      finally(function()
        helpers.unsetenv(add_header_env)
        helpers.unsetenv(add_json_env)
      end)

      helpers.setenv(add_header_env, "Access-Control-Allow-Origin:https://example.com")
      helpers.setenv(add_json_env, "server_info:kong_gateway_v3")

      local resolved_header, header_err = get("{vault://env/add_cors_header}")
      local resolved_json, json_err = get("{vault://env/add_metadata}")

      assert.is_nil(header_err)
      assert.is_nil(json_err)
      assert.equal("Access-Control-Allow-Origin:https://example.com", resolved_header)
      assert.equal("server_info:kong_gateway_v3", resolved_json)

      -- In actual usage, these resolved values would be used in:
      -- config.add.headers = ["{vault://env/add_cors_header}"]
      -- config.add.json = ["{vault://env/add_metadata}"]
    end)

    it("should handle multiple response transformation operations", function()
      finally(function()
        helpers.unsetenv("REPLACE_RESPONSE_HEADER")
        helpers.unsetenv("APPEND_RESPONSE_HEADER") 
        helpers.unsetenv("REMOVE_RESPONSE_HEADER")
        helpers.unsetenv("RENAME_RESPONSE_HEADER")
      end)

      -- Different transformation operations for responses
      helpers.setenv("REPLACE_RESPONSE_HEADER", "Server:Kong-Gateway")
      helpers.setenv("APPEND_RESPONSE_HEADER", "X-Rate-Limit-Remaining:1000")
      helpers.setenv("REMOVE_RESPONSE_HEADER", "X-Internal-Header")
      helpers.setenv("RENAME_RESPONSE_HEADER", "X-Old-Response:X-New-Response")

      local replace_res, replace_err = get("{vault://env/replace_response_header}")
      local append_res, append_err = get("{vault://env/append_response_header}")
      local remove_res, remove_err = get("{vault://env/remove_response_header}")
      local rename_res, rename_err = get("{vault://env/rename_response_header}")
      
      assert.is_nil(replace_err)
      assert.is_nil(append_err)
      assert.is_nil(remove_err)
      assert.is_nil(rename_err)
      
      assert.equal("Server:Kong-Gateway", replace_res)
      assert.equal("X-Rate-Limit-Remaining:1000", append_res)
      assert.equal("X-Internal-Header", remove_res)
      assert.equal("X-Old-Response:X-New-Response", rename_res)

      -- These would be used in configuration like:
      -- config.replace.headers = ["{vault://env/replace_response_header}"]
      -- config.append.headers = ["{vault://env/append_response_header}"]  
      -- config.remove.headers = ["{vault://env/remove_response_header}"]
      -- config.rename.headers = ["{vault://env/rename_response_header}"]
    end)

    it("should handle JSON response transformations", function()
      finally(function()
        helpers.unsetenv("ADD_JSON_FIELD")
        helpers.unsetenv("REPLACE_JSON_FIELD")
        helpers.unsetenv("REMOVE_JSON_FIELD")
        helpers.unsetenv("RENAME_JSON_FIELD")
      end)

      -- JSON transformation operations
      helpers.setenv("ADD_JSON_FIELD", "timestamp:$(now)")
      helpers.setenv("REPLACE_JSON_FIELD", "status:processed")
      helpers.setenv("REMOVE_JSON_FIELD", "internal_id")
      helpers.setenv("RENAME_JSON_FIELD", "old_field:new_field")

      local add_res, add_err = get("{vault://env/add_json_field}")
      local replace_res, replace_err = get("{vault://env/replace_json_field}")
      local remove_res, remove_err = get("{vault://env/remove_json_field}")
      local rename_res, rename_err = get("{vault://env/rename_json_field}")
      
      assert.is_nil(add_err)
      assert.is_nil(replace_err)
      assert.is_nil(remove_err)
      assert.is_nil(rename_err)
      
      assert.equal("timestamp:$(now)", add_res)
      assert.equal("status:processed", replace_res)
      assert.equal("internal_id", remove_res)
      assert.equal("old_field:new_field", rename_res)

      -- These would be used in configuration like:
      -- config.add.json = ["{vault://env/add_json_field}"]
      -- config.replace.json = ["{vault://env/replace_json_field}"]
      -- config.remove.json = ["{vault://env/remove_json_field}"]
      -- config.rename.json = ["{vault://env/rename_json_field}"]
    end)

    it("should handle security and compliance headers", function()
      finally(function()
        helpers.unsetenv("SECURITY_HEADERS_CSP")
        helpers.unsetenv("SECURITY_HEADERS_HSTS")
        helpers.unsetenv("SECURITY_HEADERS_CT")
      end)

      -- Common security headers
      helpers.setenv("SECURITY_HEADERS_CSP", "Content-Security-Policy:default-src 'self'")
      helpers.setenv("SECURITY_HEADERS_HSTS", "Strict-Transport-Security:max-age=31536000")
      helpers.setenv("SECURITY_HEADERS_CT", "Content-Type:application/json; charset=utf-8")

      local csp_res, csp_err = get("{vault://env/security_headers_csp}")
      local hsts_res, hsts_err = get("{vault://env/security_headers_hsts}")
      local ct_res, ct_err = get("{vault://env/security_headers_ct}")
      
      assert.is_nil(csp_err)
      assert.is_nil(hsts_err)
      assert.is_nil(ct_err)
      
      assert.equal("Content-Security-Policy:default-src 'self'", csp_res)
      assert.equal("Strict-Transport-Security:max-age=31536000", hsts_res)
      assert.equal("Content-Type:application/json; charset=utf-8", ct_res)

      -- These demonstrate vault usage for security compliance
    end)
  end)
end)