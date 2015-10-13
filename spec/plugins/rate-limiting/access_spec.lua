local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local timestamp = require "kong.tools.timestamp"
local cjson = require "cjson"
local constants = require "kong.constants"

local format = string.format

local STUB_GET_URL = spec_helper.STUB_GET_URL

local function wait()
  -- If the minute elapses in the middle of the test, then the test will
  -- fail. So we give it this test 30 seconds to execute, and if the second
  -- of the current minute is > 30, then we wait till the new minute kicks in
  local current_second = timestamp.get_timetable().sec
  if current_second > 30 then
    os.execute("sleep "..tostring(60 - current_second))
  end
end

describe("RateLimiting Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests-rate-limiting1", request_host = "test3.com", upstream_url = "http://mockbin.com" },
        { name = "tests-rate-limiting2", request_host = "test4.com", upstream_url = "http://mockbin.com" },
        { name = "tests-rate-limiting3", request_host = "test5.com", upstream_url = "http://mockbin.com" },
        { name = "tests-rate-limiting4", request_host = "test6.com", upstream_url = "http://mockbin.com" },
        { name = "tests-rate-limiting5", request_host = "test7.com", upstream_url = "http://mockbin.com" },
        { name = "tests-rate-limiting6", request_host = "test8.com", upstream_url = "http://mockbin.com" },
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
        { name = "rate-limiting", config = { minute = 12, hour = 16, usage_status_url = "/usu"}, __api = 5 },
        { name = "rate-limiting", config = { minute = 3, hour = 5 }, __api = 6 },
      },
      keyauth_credential = {
        { key = "apikey122", __consumer = 1 },
        { key = "apikey123", __consumer = 2 }
      }
    }

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

    end)
  end)

  describe("Rate limit usage status", function()
    it("should return json with current rate limit usage status", function()
      -- set matrics for second.
      local get_matrics_url = format("%s/%s", spec_helper.PROXY_URL, "usu")

      -- make 2 requests to the api
      http_client.get(STUB_GET_URL, {}, {host = "test7.com"})
      http_client.get(STUB_GET_URL, {}, {host = "test7.com"})

      -- get current status
      local response_json, status = http_client.get(get_matrics_url, {}, {host = "test7.com"})
      local response = cjson.decode(response_json)
      assert.are.equal(200, status)
      assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["limit-second"])
      assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["remaining-second"])

      assert.are.equal(12, response.rate["limit-minute"])
      assert.are.equal(10, response.rate["remaining-minute"])

      assert.are.equal(16, response.rate["limit-hour"])
      assert.are.equal(14, response.rate["remaining-hour"])

      assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["limit-day"])
      assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["remaining-day"])

      assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["limit-month"])
      assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["remaining-month"])

    local get_matrics_url = format("%s/%s", spec_helper.PROXY_URL, "usage_status")
      -- make 2 requests to the api
    http_client.get(STUB_GET_URL, {}, {host = "test8.com"})
    http_client.get(STUB_GET_URL, {}, {host = "test8.com"})
    local response_json, status = http_client.get(get_matrics_url, {}, {host = "test8.com"})
    local response = cjson.decode(response_json)
    assert.are.equal(200, status)
    assert.are.equal(3, response.rate["limit-minute"])
    assert.are.equal(1, response.rate["remaining-minute"])

    assert.are.equal(5, response.rate["limit-hour"])
    assert.are.equal(3, response.rate["remaining-hour"])

    assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["limit-second"])
    assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["remaining-second"])

    assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["limit-day"])
    assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["remaining-day"])

    assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["limit-month"])
    assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["remaining-month"])

    assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["limit-year"])
    assert.are.equal(constants.RATELIMIT.USAGE_STATUS.NO_LIMIT_VALUE, response.rate["remaining-year"])

    end)
  end)


end)
