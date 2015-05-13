local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL

describe("RateLimiting Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests ratelimiting 1", public_dns = "test3.com", target_url = "http://mockbin.com" },
        { name = "tests ratelimiting 2", public_dns = "test4.com", target_url = "http://mockbin.com" },
        { name = "tests ratelimiting 3", public_dns = "test5.com", target_url = "http://mockbin.com" }
      },
      consumer = {
        { custom_id = "provider_123" },
        { custom_id = "provider_124" },
        { custom_id = "provider_125" }
      },
      plugin_configuration = {
        { name = "keyauth", value = {key_names = {"apikey"}, hide_credentials = true}, __api = 1 },
        { name = "ratelimiting", value = {limit = { "minute:6" }}, __api = 1 },
        { name = "ratelimiting", value = {limit = { "minute:8" }}, __api = 1, __consumer = 1 },
        { name = "ratelimiting", value = {limit = { "minute:6" }}, __api = 2 },
        { name = "ratelimiting", value = { limit = { "minute:6", "hour:60" }}, __api = 3 }
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
      -- Default ratelimiting plugin for this API says 6/minute
      local limit = 6

      for i = 1, limit do
        local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
        assert.are.equal(200, status)
        assert.are.same(tostring(limit), headers["x-ratelimit-minute-limit"])
        assert.are.same(tostring(limit - i), headers["x-ratelimit-minute-remaining"])
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
        -- Default ratelimiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-minute-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-minute-remaining"])
        end

        -- Third query, while limit is 2/minute
        local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test3.com"})
        local body = cjson.decode(response)
        assert.are.same(tostring(limit), headers["x-ratelimit-minute-limit"])
        assert.are.same(tostring(0), headers["x-ratelimit-minute-remaining"])
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)

    describe("Plugin customized for specific consumer", function()

      it("should get blocked if exceeding limit", function()
        -- This plugin says this consumer can make 8 requests/minute, not 6 like the default
        local limit = 8

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-minute-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-minute-remaining"])
        end

        local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test3.com"})
        local body = cjson.decode(response)
        assert.are.same(tostring(limit), headers["x-ratelimit-minute-limit"])
        assert.are.same(tostring(0), headers["x-ratelimit-minute-remaining"])
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)

    describe("Plugin with multiple ratelimiting configs", function()

      it("should get blocked if exceeding limit even for one limit", function()
        local minute_limit = 6
        local hour_limit = 60

        for i = 1, minute_limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey124"}, {host = "test5.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(minute_limit), headers["x-ratelimit-minute-limit"])
          assert.are.same(tostring(minute_limit - i), headers["x-ratelimit-minute-remaining"])
          assert.are.same(tostring(hour_limit), headers["x-ratelimit-hour-limit"])
          assert.are.same(tostring(hour_limit - i), headers["x-ratelimit-hour-remaining"])
        end

        local response, status, headers = http_client.get(STUB_GET_URL,  {apikey = "apikey124"}, {host = "test5.com"})
        local body = cjson.decode(response)
        assert.are.same(tostring(minute_limit), headers["x-ratelimit-minute-limit"])
        assert.are.same(tostring(0), headers["x-ratelimit-minute-remaining"])
        assert.are.same(tostring(hour_limit), headers["x-ratelimit-hour-limit"])
        assert.are.same(tostring(hour_limit - minute_limit - 1), headers["x-ratelimit-hour-remaining"])
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)
  end)
end)
