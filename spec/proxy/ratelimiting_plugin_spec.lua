local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local kProxyURL = spec_helper.PROXY_URL
local kGetURL = kProxyURL.."/get"

describe("RateLimiting Plugin #proxy", function()

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
      -- Default ratelimiting plugin for this API says 2/minute
      local limit = 2

      for i = 1, limit do
        local response, status, headers = http_client.get(kGetURL, {}, {host = "test5.com"})
        assert.are.equal(200, status)
        assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
        assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
      end

      -- Third query, while limit is 2/minute
      local response, status, headers = http_client.get(kGetURL, {}, {host = "test5.com"})
      local body = cjson.decode(response)
      assert.are.equal(429, status)
      assert.are.equal("API rate limit exceeded", body.message)
    end)

  end)

  describe("With authentication", function()

    describe("Default plugin", function()

      it("should get blocked if exceeding limit", function()
        -- Default ratelimiting plugin for this API says 2/minute
        local limit = 2

        for i = 1, limit do
          local response, status, headers = http_client.get(kGetURL, {apikey = "apikey122"}, {host = "test6.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        -- Third query, while limit is 2/minute
        local response, status, headers = http_client.get(kGetURL, {apikey = "apikey122"}, {host = "test6.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)

    describe("Plugin customized for specific application", function()

      it("should get blocked if exceeding limit", function()
        -- This plugin says this application can make 4 requests/minute, not 2 like fault
        local limit = 4

        for i = 1, limit do
          local response, status, headers = http_client.get(kGetURL, {apikey = "apikey123"}, {host = "test6.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        local response, status, headers = http_client.get(kGetURL, {apikey = "apikey123"}, {host = "test6.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)
  end)
end)
