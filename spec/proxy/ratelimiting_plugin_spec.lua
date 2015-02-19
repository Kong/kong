local utils = require "kong.tools.utils"
local cjson = require "cjson"

local kProxyURL = "http://localhost:8000/"
local kGetURL = kProxyURL.."/get"

describe("RateLimiting Plugin #proxy", function()

  describe("Without authentication (IP address)", function()

    it("should get blocked if exceeding limit", function()
      -- Default ratelimiting plugin for this API says 2/minute
      local limit = 2

      for i = 1, limit do
        local response, status, headers = utils.get(kGetURL, {}, {host = "test5.com"})
        assert.are.equal(200, status)
        assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
        assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
      end

      -- Third query, while limit is 2/minute
      local response, status, headers = utils.get(kGetURL, {}, {host = "test5.com"})
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
          local response, status, headers = utils.get(kGetURL, {apikey = "apikey122"}, {host = "test6.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        -- Third query, while limit is 2/minute
        local response, status, headers = utils.get(kGetURL, {apikey = "apikey122"}, {host = "test6.com"})
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
          local response, status, headers = utils.get(kGetURL, {apikey = "apikey123"}, {host = "test6.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        local response, status, headers = utils.get(kGetURL, {apikey = "apikey123"}, {host = "test6.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)
  end)
end)
