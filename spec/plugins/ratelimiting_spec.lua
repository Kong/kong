local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL

describe("RateLimiting Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Without authentication (IP address)", function()

    it("should get blocked if exceeding limit", function()
      -- Default ratelimiting plugin for this API says 6/minute
      local limit = 6

      for i = 1, limit do
        local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
        assert.are.equal(200, status)
        assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
        assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
      end

      -- Additonal request, while limit is 6/minute
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
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
          local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        -- Third query, while limit is 2/minute
        local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test3.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)

    describe("Plugin customized for specific consumer", function()

      it("should get blocked if exceeding limit", function()
        -- This plugin says this consumer can make 4 requests/minute, not 6 like the default
        local limit = 8

        for i = 1, limit do
          local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test3.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)
  end)
end)
