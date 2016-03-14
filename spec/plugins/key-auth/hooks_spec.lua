local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local cache = require "kong.tools.database_cache"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local API_URL = spec_helper.API_URL

describe("Key Authentication Hooks", function()

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
        {request_host = "keyauth.com", upstream_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "consumer1"}
      },
      plugin = {
        {name = "key-auth", config = {}, __api = 1}
      },
      keyauth_credential = {
        {key = "key123", __consumer = 1}
      }
    }
  end)

  describe("Key Auth Credentials entity invalidation", function()
    it("should invalidate when Key Auth Credential entity is deleted", function()
      -- It should work
      local _, status = http_client.get(STUB_GET_URL, {apikey="key123"}, {host="keyauth.com"})
      assert.equals(200, status)

      -- Check that cache is populated
      local cache_key = cache.keyauth_credential_key("key123")
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve credential ID
      local response, status = http_client.get(API_URL.."/consumers/consumer1/key-auth/")
      assert.equals(200, status)
      local credential_id = json.decode(response).data[1].id
      assert.truthy(credential_id)

      -- Delete Key Auth credential (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/consumers/consumer1/key-auth/"..credential_id)
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
      local _, status = http_client.get(STUB_GET_URL, {apikey="key123"}, {host="keyauth.com"})
      assert.equals(403, status)
    end)
    it("should invalidate when Key Auth Credential entity is updated", function()
      -- It should work
      local _, status = http_client.get(STUB_GET_URL, {apikey="key123"}, {host="keyauth.com"})
      assert.equals(200, status)

      -- It should not work
      local _, status = http_client.get(STUB_GET_URL, {apikey="updkey123"}, {host="keyauth.com"})
      assert.equals(403, status)

      -- Check that cache is populated
      local cache_key = cache.keyauth_credential_key("key123")
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve credential ID
      local response, status = http_client.get(API_URL.."/consumers/consumer1/key-auth/")
      assert.equals(200, status)
      local credential_id = json.decode(response).data[1].id
      assert.truthy(credential_id)
      
      -- Delete Key Auth credential (which triggers invalidation)
      local _, status = http_client.patch(API_URL.."/consumers/consumer1/key-auth/"..credential_id, {key="updkey123"})
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
      local _, status = http_client.get(STUB_GET_URL, {apikey="updkey123"}, {host="keyauth.com"})
      assert.equals(200, status)

      -- It should not work
      local _, status = http_client.get(STUB_GET_URL, {apikey="key123"}, {host="keyauth.com"})
      assert.equals(403, status)
    end)
  end)

  describe("Consumer entity invalidation", function()
    it("should invalidate when Consumer entity is deleted", function()
      -- It should work
      local _, status = http_client.get(STUB_GET_URL, {apikey="key123"}, {host="keyauth.com"})
      assert.equals(200, status)

      -- Check that cache is populated
      local cache_key = cache.keyauth_credential_key("key123")
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)
      
      -- Delete Consumer (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/consumers/consumer1")
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
      local _, status = http_client.get(STUB_GET_URL, {apikey="key123"}, {host="keyauth.com"})
      assert.equals(403, status)
    end)
  end)
end)
