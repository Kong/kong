local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local cache = require "kong.tools.database_cache"
local base64 = require "base64"
local crypto = require "crypto"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local API_URL = spec_helper.API_URL

describe("HMAC Authentication Hooks", function()

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
        {request_host = "hmacauth.com", upstream_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "consumer1"}
      },
      plugin = {
        {name = "hmac-auth", config = {clock_skew = 3000}, __api = 1}
      },
      hmacauth_credential = {
        {username = "bob", secret = "secret", __consumer = 1}
      }
    }
  end)

  local function hmac_sha1_binary(secret, data)
    return crypto.hmac.digest("sha1", data, secret, true)
  end

  local function get_authorization(username)
    local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
    local encodedSignature   = base64.encode(hmac_sha1_binary("secret", "date: "..date))
    return [["hmac username="]]..username..[[",algorithm="hmac-sha1",headers="date",signature="]]..encodedSignature..[["]], date
  end

  describe("HMAC Auth Credentials entity invalidation", function()
    it("should invalidate when Hmac Auth Credential entity is deleted", function()
      -- It should work
      local authorization, date = get_authorization("bob")
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = authorization})
      assert.equals(200, status)

      -- Check that cache is populated
      local cache_key = cache.hmacauth_credential_key("bob")
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve credential ID
      local response, status = http_client.get(API_URL.."/consumers/consumer1/hmac-auth/")
      assert.equals(200, status)
      local credential_id = json.decode(response).data[1].id
      assert.truthy(credential_id)
      
      -- Delete Hmac Auth credential (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/consumers/consumer1/hmac-auth/"..credential_id)
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
      local authorization, date = get_authorization("bob")
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = authorization})
      assert.equals(403, status)
    end)
    it("should invalidate when Hmac Auth Credential entity is updated", function()
      -- It should work
      local authorization, date = get_authorization("bob")
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = authorization})
      assert.equals(200, status)

      -- It should not work
      local authorization, date = get_authorization("hello123")
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = authorization})
      assert.equals(403, status)

      -- Check that cache is populated
      local cache_key = cache.hmacauth_credential_key("bob")
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)

      -- Retrieve credential ID
      local response, status = http_client.get(API_URL.."/consumers/consumer1/hmac-auth/")
      assert.equals(200, status)
      local credential_id = json.decode(response).data[1].id
      assert.truthy(credential_id)
      
      -- Delete Hmac Auth credential (which triggers invalidation)
      local _, status = http_client.patch(API_URL.."/consumers/consumer1/hmac-auth/"..credential_id, {username="hello123"})
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
      local authorization, date = get_authorization("hello123")
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = authorization})
      assert.equals(200, status)

      -- It should not work
      local authorization, date = get_authorization("bob")
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = authorization})
      assert.equals(403, status)
    end)
  end)
  describe("Consumer entity invalidation", function()
    it("should invalidate when Consumer entity is deleted", function()
      -- It should work
      local authorization, date = get_authorization("bob")
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = authorization})
      assert.equals(200, status)

      -- Check that cache is populated
      local cache_key = cache.hmacauth_credential_key("bob")
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
      local authorization, date = get_authorization("bob")
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hmacauth.com",  date = date, authorization = authorization})
      assert.equals(403, status)
    end)
  end)
end)
