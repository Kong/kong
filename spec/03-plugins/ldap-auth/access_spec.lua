local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local base64 = require "base64"
local cache = require "kong.tools.database_cache"

local PROXY_URL = spec_helper.PROXY_URL
local API_URL = spec_helper.API_URL

describe("LDAP-AUTH Plugin", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "test-ldap", request_host = "ldap.com", upstream_url = "http://mockbin.com"},
        {name = "test-ldap2", request_host = "ldap2.com", upstream_url = "http://mockbin.com"}
      },
      plugin = {
        {name = "ldap-auth", config = {ldap_host = "ldap.forumsys.com", ldap_port = "389", start_tls = false, base_dn = "dc=example,dc=com", attribute = "uid"}, __api = 1},
        {name = "ldap-auth", config = {ldap_host = "ldap.forumsys.com", ldap_port = "389", start_tls = false, base_dn = "dc=example,dc=com", attribute = "uid", hide_credentials = true}, __api = 2},
      }
    }
  
    spec_helper.start_kong()
  end)
  
  teardown(function()
    spec_helper.stop_kong()
  end)
  
  describe("ldap-auth", function()
    it("should return invalid credentials and www-authenticate header when the credential is missing", function()
      local response, status, headers = http_client.get(PROXY_URL.."/get", {}, {host = "ldap.com"})
      assert.equal(401, status)
      local body = cjson.decode(response)
      assert.equal(headers["www-authenticate"], 'LDAP realm="kong"')
      assert.equal("Unauthorized", body.message)
    end)
  
    it("should return invalid credentials when credential value is in wrong format in authorization header", function()
      local response, status = http_client.get(PROXY_URL.."/get", {}, {host = "ldap.com", authorization = "abcd"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("Invalid authentication credentials", body.message)
    end)
  
    it("should return invalid credentials when credential value is in wrong format in proxy-authorization header", function()
      local response, status = http_client.get(PROXY_URL.."/get", {}, {host = "ldap.com", ["proxy-authorization"] = "abcd"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("Invalid authentication credentials", body.message)
    end)
  
    it("should return invalid credentials when credential value is missing in authorization header", function()
      local _, status = http_client.get(PROXY_URL.."/get", {}, {host = "ldap.com", authorization = "ldap "})
      assert.equal(403, status)
    end)
  
    it("should pass if credential is valid in post request", function()
      local _, status = http_client.post(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password")})
      assert.equal(200, status)
    end)
  
    it("should pass if credential is valid and starts with space in post request", function()
      local _, status = http_client.post(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = " ldap "..base64.encode("einstein:password")})
      assert.equal(200, status)
    end)
  
    it("should pass if signature type indicator is in caps and credential is valid in post request", function()
      local _, status = http_client.post(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "LDAP "..base64.encode("einstein:password")})
      assert.equal(200, status)
    end)
  
    it("should pass if credential is valid in get request", function()
      local response, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password")})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.truthy(parsed_response.headers["x-credential-username"])
      assert.equal("einstein", parsed_response.headers["x-credential-username"])
    end)
  
    it("should not pass if credential does not has password encoded in get request", function()
      local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:")})
      assert.equal(403, status)
    end)
  
    it("should not pass if credential has multiple encoded username or password separated by ':' in get request", function()
      local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password:another_password")})
      assert.equal(403, status)
    end)
  
    it("should not pass if credential is invalid in get request", function()
      local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:wrong_password")})
      assert.equal(403, status)
    end)
    
    it("should not hide credential sent along with authorization header to upstream server", function()
      local response, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password")})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.equal("ldap "..base64.encode("einstein:password"), parsed_response.headers["authorization"])
    end)
    
    it("should hide credential sent along with authorization header to upstream server", function()
      local response, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap2.com", authorization = "ldap "..base64.encode("einstein:password")})
      assert.equal(200, status)
      local parsed_response = cjson.decode(response)
      assert.falsy(parsed_response.headers["authorization"])
    end)
    
    it("should cache LDAP Auth Credential", function()
      local _, status = http_client.get(PROXY_URL.."/request", {}, {host = "ldap.com", authorization = "ldap "..base64.encode("einstein:password")})
      assert.equals(200, status)
            
      -- Check that cache is populated
      local cache_key = cache.ldap_credential_key("einstein")
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end
      assert.equals(200, status)
    end)
  end)
end)
