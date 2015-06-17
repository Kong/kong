local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL

local function wait()
  -- Wait til the beginning of a new second before starting the test
  -- to avoid ending up in an edge case when the second is about to end
  local now = os.time()
  while os.time() < now + 1 do
    -- Nothing
  end
end

describe("RateLimiting Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests ratelimiting 1", public_dns = "test3.com", target_url = "http://mockbin.com" },
        { name = "tests ratelimiting 2", public_dns = "test4.com", target_url = "http://mockbin.com" }
      },
      consumer = {
        { custom_id = "provider_123" },
        { custom_id = "provider_124" }
      },
      plugin_configuration = {
        { name = "keyauth", value = {key_names = {"apikey"}, hide_credentials = true}, __api = 1 },
        { name = "ratelimiting", value = {period = "minute", limit = 6}, __api = 1 },
        { name = "ratelimiting", value = {period = "minute", limit = 8}, __api = 1, __consumer = 1 },
        { name = "ratelimiting", value = {period = "minute", limit = 6}, __api = 2 },
      },
      keyauth_credential = {
        { key = "apikey122", __consumer = 1 },
        { key = "apikey123", __consumer = 2 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Without authentication (IP address)", function()

    it("should get blocked if exceeding limit", function()
      wait()

      -- Default ratelimiting plugin for this API says 6/minute
      local limit = 6

      for i = 1, limit do
        local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
        assert.are.equal(200, status)
        assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
        assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
      end

      -- Additonal request, while limit is 6/minute
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
      local body = cjson.decode(response)
      assert.are.equal(429, status)
      assert.are.equal("API rate limit exceeded", body.message)
    end)

  end)

  describe("With authentication", function()

    describe("Default plugin", function()

      it("should get blocked if exceeding limit", function()
        wait()
        
        -- Default ratelimiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        -- Third query, while limit is 2/minute
        local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test3.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)

    describe("Plugin customized for specific consumer", function()

      it("should get blocked if exceeding limit", function()
        wait()

        -- This plugin says this consumer can make 4 requests/minute, not 6 like the default
        local limit = 8

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test3.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)
  end)
end)
