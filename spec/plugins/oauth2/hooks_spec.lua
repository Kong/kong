local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local cache = require "kong.tools.database_cache"
local rex = require "rex_pcre"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local PROXY_SSL_URL = spec_helper.PROXY_SSL_URL
local API_URL = spec_helper.API_URL

local env = spec_helper.get_env() -- test environment
local dao_factory = env.dao_factory
local configuration = env.configuration
configuration.cassandra = configuration[configuration.database].properties

describe("OAuth2 Authentication Hooks", function()

  setup(function()
    spec_helper.prepare_db()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  before_each(function()
    spec_helper.restart_kong()

    spec_helper.drop_db()
    spec_helper.insert_fixtures {
      api = {
        { request_host = "oauth2.com", upstream_url = "http://mockbin.com" }
      },
      consumer = {
        { username = "auth_tests_consumer" }
      },
      plugin = {
        { name = "oauth2", config = { scopes = { "email", "profile" }, mandatory_scope = true, provision_key = "provision123", token_expiration = 5, enable_implicit_grant = true }, __api = 1 }
      },
      oauth2_credential = {
        { client_id = "clientid123", client_secret = "secret123", redirect_uri = "http://google.com/kong", name="testapp", __consumer = 1 }
      }
    }
  end)

  local function provision_code(client_id)
    local response = http_client.post(PROXY_SSL_URL.."/oauth2/authorize", { provision_key = "provision123", client_id = client_id, scope = "email", response_type = "code", state = "hello", authenticated_userid = "userid123" }, {host = "oauth2.com"})
    local body = json.decode(response)
    if body.redirect_uri then
      local matches = rex.gmatch(body.redirect_uri, "^http://google\\.com/kong\\?code=([\\w]{32,32})&state=hello$")
      local code
      for line in matches do
        code = line
      end
      local data = dao_factory.oauth2_authorization_codes:find_all({code = code})
      return data[1].code
    end
  end

  describe("OAuth2 Credentials entity invalidation", function()
    it("should invalidate when OAuth2 Credential entity is deleted", function()
      -- It should work
      local code = provision_code("clientid123")
      local _, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(200, status)

      -- Check that cache is populated
      local cache_key = cache.oauth2_credential_key("clientid123")
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve credential ID
      local response, status = http_client.get(API_URL.."/consumers/auth_tests_consumer/oauth2/")
      assert.equals(200, status)
      local credential_id = json.decode(response).data[1].id
      assert.truthy(credential_id)

      -- Delete OAuth2 credential (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/consumers/auth_tests_consumer/oauth2/"..credential_id)
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local code = provision_code("clientid123")
      local _, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(400, status)
    end)
    it("should invalidate when OAuth2 Credential entity is updated", function()
      -- It should work
      local code = provision_code("clientid123")
      local _, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(200, status)

       -- It should not work
      local code = provision_code("updclientid123")
      local _, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "updclientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(400, status)

      -- Check that cache is populated
      local cache_key = cache.oauth2_credential_key("clientid123")
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve credential ID
      local response, status = http_client.get(API_URL.."/consumers/auth_tests_consumer/oauth2/")
      assert.equals(200, status)
      local credential_id = json.decode(response).data[1].id
      assert.truthy(credential_id)

      -- Update OAuth2 credential (which triggers invalidation)
      local _, status = http_client.patch(API_URL.."/consumers/auth_tests_consumer/oauth2/"..credential_id, {client_id="updclientid123"})
      assert.equals(200, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should work
      local code = provision_code("updclientid123")
      local _, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "updclientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(200, status)

      -- It should not work
      local code = provision_code("clientid123")
      local _, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(400, status)
    end)
  end)

  describe("Consumer entity invalidation", function()
    it("should invalidate when Consumer entity is deleted", function()
      -- It should work
      local code = provision_code("clientid123")
      local _, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(200, status)

      -- Check that cache is populated
      local cache_key = cache.oauth2_credential_key("clientid123")
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Delete Consumer (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/consumers/auth_tests_consumer")
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local code = provision_code("clientid123")
      local _, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(400, status)
    end)
  end)

  describe("OAuth2 access token entity invalidation", function()
    it("should invalidate when OAuth2 token entity is deleted", function()
      -- It should work
      local code = provision_code("clientid123")
      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(200, status)
      local token = json.decode(response)
      assert.truthy(token)

      local _, status = http_client.post(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      assert.are.equal(200, status)

      -- Check that cache is populated
      local cache_key = cache.oauth2_token_key(token.access_token)
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Delete token (which triggers invalidation)
      local res = dao_factory.oauth2_tokens:find_all({access_token=token.access_token})
      local token_id = res[1].id
      assert.truthy(token_id)

      local _, status = http_client.delete(API_URL.."/oauth2_tokens/"..token_id)
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local _, status = http_client.post(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      assert.are.equal(401, status)
    end)
    it("should invalidate when Oauth2 token entity is updated", function()
      -- It should work
      local code = provision_code("clientid123")
      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(200, status)
      local token = json.decode(response)
      assert.truthy(token)

      local _, status = http_client.post(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      assert.are.equal(200, status)

       -- It should not work
      local _, status = http_client.post(STUB_GET_URL, { access_token = "hello_token" }, {host = "oauth2.com"})
      assert.are.equal(401, status)

      -- Check that cache is populated
      local cache_key = cache.oauth2_token_key(token.access_token)
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Update OAuth 2 token (which triggers invalidation)
      local res = dao_factory.oauth2_tokens:find_all({access_token=token.access_token})
      local token_id = res[1].id
      assert.truthy(token_id)

      local _, status = http_client.patch(API_URL.."/oauth2_tokens/"..token_id, {access_token="hello_token"})
      assert.equals(200, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should work
      local _, status = http_client.post(STUB_GET_URL, { access_token = "hello_token" }, {host = "oauth2.com"})
      assert.are.equal(200, status)

      -- It should not work
      local _, status = http_client.post(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      assert.are.equal(401, status)
    end)
  end)

  describe("OAuth2 client entity invalidation", function()
    it("should invalidate token when OAuth2 client entity is deleted", function()
      -- It should work
      local code = provision_code("clientid123")
      local response, status = http_client.post(PROXY_SSL_URL.."/oauth2/token", { code = code, client_id = "clientid123", client_secret = "secret123", grant_type = "authorization_code" }, {host = "oauth2.com"})
      assert.are.equal(200, status)
      local token = json.decode(response)
      assert.truthy(token)

      local _, status = http_client.post(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      assert.are.equal(200, status)

      -- Check that cache is populated
      local cache_key = cache.oauth2_token_key(token.access_token)
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve credential ID
      local response, status = http_client.get(API_URL.."/consumers/auth_tests_consumer/oauth2/", {client_id="clientid123"})
      assert.equals(200, status)
      local credential_id = json.decode(response).data[1].id
      assert.truthy(credential_id)

      -- Delete OAuth2 client (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/consumers/auth_tests_consumer/oauth2/"..credential_id)
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local _, status = http_client.post(STUB_GET_URL, { access_token = token.access_token }, {host = "oauth2.com"})
      assert.are.equal(401, status)
    end)
  end)

end)
