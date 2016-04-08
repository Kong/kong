local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local timestamp = require "kong.tools.timestamp"
local cjson = require "cjson"

local env = spec_helper.get_env()
local dao_factory = env.dao_factory

local STUB_GET_URL = spec_helper.STUB_GET_URL

local function wait()
  -- If the minute elapses in the middle of the test, then the test will
  -- fail. So we give it this test 30 seconds to execute, and if the second
  -- of the current minute is > 30, then we wait till the new minute kicks in
  local current_second = timestamp.get_timetable().sec
  if current_second > 20 then
    os.execute("sleep "..tostring(60 - current_second))
  end
end

describe("RateLimiting Plugin", function()

  local function prepare_db()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { request_host = "test3.com", upstream_url = "http://mockbin.com" },
        { request_host = "test4.com", upstream_url = "http://mockbin.com" },
        { request_host = "test5.com", upstream_url = "http://mockbin.com" },
        { request_host = "test6.com", upstream_url = "http://mockbin.com" },
        { request_host = "test7.com", upstream_url = "http://mockbin.com" },
        { request_host = "test8.com", upstream_url = "http://mockbin.com" },
        { request_host = "test9.com", upstream_url = "http://mockbin.com" },
        { request_host = "test10.com", upstream_url = "http://mockbin.com" }
      },
      consumer = {
        { custom_id = "provider_123" },
        { custom_id = "provider_124" }
      },
      plugin = {
        { name = "key-auth", config = {key_names = {"apikey"}, hide_credentials = true}, __api = 1 },
        { name = "rate-limiting", config = { minute = 6 }, __api = 1 },
        { name = "rate-limiting", config = { minute = 8 }, __api = 1, __consumer = 1 },
        { name = "rate-limiting", config = { minute = 6 }, __api = 2 },
        { name = "rate-limiting", config = { minute = 3, hour = 5 }, __api = 3 },
        { name = "rate-limiting", config = { minute = 33 }, __api = 4 },
        { name = "rate-limiting", config = { minute = 6, async = true }, __api = 5 },
        { name = "rate-limiting", config = { minute = 6, continue_on_error = false }, __api = 6 },
        { name = "rate-limiting", config = { minute = 6, continue_on_error = true }, __api = 7 },
        { name = "key-auth", config = {}, __api = 8 },
        { name = "rate-limiting", config = { minute = 6, continue_on_error = true }, __api = 8, __consumer = 1 }
      },
      keyauth_credential = {
        { key = "apikey122", __consumer = 1 },
        { key = "apikey123", __consumer = 2 }
      }
    }
  end

  setup(function()
    dao_factory:drop_schema()
    prepare_db()
    spec_helper.start_kong()
    wait()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Without authentication (IP address)", function()

    it("should get blocked if exceeding limit", function()
      -- Default rate-limiting plugin for this API says 6/minute
      local limit = 6

      for i = 1, limit do
        local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
        assert.are.equal(200, status)
        assert.are.same(tostring(limit), headers["x-ratelimit-limit-minute"])
        assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-minute"])
      end

      -- Additonal request, while limit is 6/minute
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
      local body = cjson.decode(response)
      assert.are.equal(429, status)
      assert.are.equal("API rate limit exceeded", body.message)
    end)

    it("should handle multiple limits", function()
      local limits = {
        minute = 3,
        hour = 5
      }

      for i = 1, 3 do
        local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test5.com"})
        assert.are.equal(200, status)

        assert.are.same(tostring(limits.minute), headers["x-ratelimit-limit-minute"])
        assert.are.same(tostring(limits.minute - i), headers["x-ratelimit-remaining-minute"])
        assert.are.same(tostring(limits.hour), headers["x-ratelimit-limit-hour"])
        assert.are.same(tostring(limits.hour - i), headers["x-ratelimit-remaining-hour"])
      end

      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test5.com"})
      assert.are.equal("2", headers["x-ratelimit-remaining-hour"])
      assert.are.equal("0", headers["x-ratelimit-remaining-minute"])
      local body = cjson.decode(response)
      assert.are.equal(429, status)
      assert.are.equal("API rate limit exceeded", body.message)
    end)

  end)

  describe("With authentication", function()
    describe("Default plugin", function()
      it("should get blocked if exceeding limit", function()
        -- Default rate-limiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit-minute"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-minute"])
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
        -- This plugin says this consumer can make 4 requests/minute, not 6 like the default
        local limit = 8

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit-minute"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-minute"])
        end

        local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test3.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)
      it("should get blocked if the only rate-limiting plugin existing is per consumer and not per API", function()
        -- This plugin says this consumer can make 4 requests/minute, not 6 like the default
        local limit = 6

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test10.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit-minute"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-minute"])
        end

        local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey122"}, {host = "test10.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)
    end)
  end)

  describe("Async increment", function()
    it("should increment asynchronously", function()
      -- Default rate-limiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test7.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit-minute"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-minute"])
          os.execute("sleep 3") -- Wait for timers to increment
        end

        local response, status = http_client.get(STUB_GET_URL, {}, {host = "test7.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
    end)
  end)

  describe("Continue on error", function()
    after_each(function()
      dao_factory:drop_schema()
      prepare_db()
    end)

    it("should not continue if an error occurs", function()
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test8.com"})
      assert.are.equal(200, status)
      assert.are.same(tostring(6), headers["x-ratelimit-limit-minute"])
      assert.are.same(tostring(5), headers["x-ratelimit-remaining-minute"])

      -- Simulate an error on the database
      local err = dao_factory.ratelimiting_metrics:drop_table(dao_factory.ratelimiting_metrics.table)
      assert.falsy(err)

      -- Make another request
      local res, status, _ = http_client.get(STUB_GET_URL, {}, {host = "test8.com"})
      assert.equal("An unexpected error occurred", cjson.decode(res).message)
      assert.are.equal(500, status)
    end)

    it("should continue if an error occurs", function()
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test9.com"})
      assert.are.equal(200, status)
      assert.falsy(headers["x-ratelimit-limit-minute"])
      assert.falsy(headers["x-ratelimit-remaining-minute"])

      -- Simulate an error on the database
      local err = dao_factory.ratelimiting_metrics:drop_table(dao_factory.ratelimiting_metrics.table)
      assert.falsy(err)

      -- Make another request
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test9.com"})
      assert.are.equal(200, status)
      assert.falsy(headers["x-ratelimit-limit-minute"])
      assert.falsy(headers["x-ratelimit-remaining-minute"])
    end)
  end)

end)
