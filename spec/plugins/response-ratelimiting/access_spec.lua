local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local timestamp = require "kong.tools.timestamp"
local cjson = require "cjson"

local env = spec_helper.get_env()
local dao_factory = env.dao_factory

local PROXY_URL = spec_helper.PROXY_URL
local SLEEP_VALUE = "0.5"

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
        { name = "tests-response-ratelimiting1", request_host = "test1.com", upstream_url = "http://httpbin.org/" },
        { name = "tests-response-ratelimiting2", request_host = "test2.com", upstream_url = "http://httpbin.org/" },
        { name = "tests-response-ratelimiting3", request_host = "test3.com", upstream_url = "http://httpbin.org/" },
        { name = "tests-response-ratelimiting4", request_host = "test4.com", upstream_url = "http://httpbin.org/" },
        { name = "tests-response-ratelimiting5", request_host = "test5.com", upstream_url = "http://httpbin.org/" },
        { name = "tests-response-ratelimiting6", request_host = "test6.com", upstream_url = "http://httpbin.org/" },
        { name = "tests-response-ratelimiting7", request_host = "test7.com", upstream_url = "http://httpbin.org/" },
        { name = "tests-response-ratelimiting8", request_host = "test8.com", upstream_url = "http://httpbin.org/" }
      },
      consumer = {
        { custom_id = "consumer_123" },
        { custom_id = "consumer_124" },
        { custom_id = "consumer_125" }
      },
      plugin = {
        { name = "response-ratelimiting", config = { limits = { video = { minute = 6 } } }, __api = 1 },
        { name = "response-ratelimiting", config = { limits = { video = { minute = 6, hour = 10 }, image = { minute = 4 } } }, __api = 2 },
        { name = "key-auth", config = {key_names = {"apikey"}, hide_credentials = true}, __api = 3 },
        { name = "response-ratelimiting", config = { limits = { video = { minute = 6 } } }, __api = 3 },
        { name = "response-ratelimiting", config = { limits = { video = { minute = 2 } } }, __api = 3, __consumer = 1 },
        { name = "response-ratelimiting", config = { continue_on_error = false, limits = { video = { minute = 6 } } }, __api = 4 },
        { name = "response-ratelimiting", config = { continue_on_error = true, limits = { video = { minute = 6 } } }, __api = 5 },
        { name = "response-ratelimiting", config = { continue_on_error = true, limits = { video = { minute = 2 } } }, __api = 6 },
        { name = "response-ratelimiting", config = { continue_on_error = false, block_on_first_violation = true, limits = { video = { minute = 6, hour = 10 }, image = { minute = 4 } } }, __api = 7 },
        { name = "response-ratelimiting", config = { limits = { video = { minute = 6, hour = 10 }, image = { minute = 4 } } }, __api = 8 }
      },
      keyauth_credential = {
        { key = "apikey123", __consumer = 1 },
        { key = "apikey124", __consumer = 2 },
        { key = "apikey125", __consumer = 3 }
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
      -- Default ratelimiting plugin for this API says 6/minute
      local limit = 6

      for i = 1, limit do
        local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=1, test=5"}, {host = "test1.com"})
        assert.are.equal(200, status)
        assert.are.same(tostring(limit), headers["x-ratelimit-limit-video-minute"])
        assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-video-minute"])
        os.execute("sleep "..SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
      end

      -- Additonal request, while limit is 6/minute
      local _, status = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=1"}, {host = "test1.com"})
      assert.are.equal(429, status)
    end)

    it("should handle multiple limits", function()
      for i = 1, 3 do
        local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=2, image = 1"}, {host = "test2.com"})
        assert.are.equal(200, status)

        assert.are.same(tostring(6), headers["x-ratelimit-limit-video-minute"])
        assert.are.same(tostring(6 - (i * 2)), headers["x-ratelimit-remaining-video-minute"])
        assert.are.same(tostring(10), headers["x-ratelimit-limit-video-hour"])
        assert.are.same(tostring(10 - (i * 2)), headers["x-ratelimit-remaining-video-hour"])
        assert.are.same(tostring(4), headers["x-ratelimit-limit-image-minute"])
        assert.are.same(tostring(4 - i), headers["x-ratelimit-remaining-image-minute"])
        os.execute("sleep "..SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
      end

      local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=2, image = 1"}, {host = "test2.com"})

      assert.are.equal(429, status)
      assert.are.equal("0", headers["x-ratelimit-remaining-video-minute"])
      assert.are.equal("4", headers["x-ratelimit-remaining-video-hour"])
      assert.are.equal("1", headers["x-ratelimit-remaining-image-minute"])
    end)
  end)

  describe("With authentication", function()
    describe("Default plugin", function()
      it("should get blocked if exceeding limit and a per consumer setting", function()
        -- Default ratelimiting plugin for this API says 6/minute
        local limit = 2

        for i = 1, limit do
          local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {apikey = "apikey123", ["x-kong-limit"] = "video=1"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit-video-minute"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-video-minute"])
          os.execute("sleep "..SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
        end

        -- Third query, while limit is 2/minute
        local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {apikey = "apikey123", ["x-kong-limit"] = "video=1"}, {host = "test3.com"})
        assert.are.equal(429, status)
        assert.are.equal("0", headers["x-ratelimit-remaining-video-minute"])
        assert.are.equal("2", headers["x-ratelimit-limit-video-minute"])
      end)

      it("should not get blocked if the last request doesn't increment", function()
        -- Default ratelimiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {apikey = "apikey124", ["x-kong-limit"] = "video=1"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit-video-minute"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-video-minute"])
          os.execute("sleep "..SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
        end

        -- Third query, while limit is 2/minute
        local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {apikey = "apikey124"}, {host = "test3.com"})
        assert.are.equal(200, status)
        assert.are.equal("0", headers["x-ratelimit-remaining-video-minute"])
        assert.are.equal("6", headers["x-ratelimit-limit-video-minute"])
      end)

      it("should get blocked if exceeding limit", function()
        -- Default ratelimiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {apikey = "apikey125", ["x-kong-limit"] = "video=1"}, {host = "test3.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit-video-minute"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining-video-minute"])
          os.execute("sleep "..SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
        end

        -- Third query, while limit is 2/minute
        local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {apikey = "apikey125", ["x-kong-limit"] = "video=1"}, {host = "test3.com"})
        assert.are.equal(429, status)
        assert.are.equal("0", headers["x-ratelimit-remaining-video-minute"])
        assert.are.equal("6", headers["x-ratelimit-limit-video-minute"])
      end)
    end)
  end)

  describe("Upstream usage headers", function()
    it("should append the headers with multiple limits", function()
      local response, status = http_client.get(PROXY_URL.."/get", {}, {host = "test8.com"})
      assert.are.equal(200, status)
      local body = cjson.decode(response)
      assert.are.equal("4", body.headers["X-Ratelimit-Remaining-Image"])
      assert.are.equal("6", body.headers["X-Ratelimit-Remaining-Video"])

      -- Actually consume the limits
      local _, status = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=2, image=1"}, {host = "test8.com"})
      assert.are.equal(200, status)

      os.execute("sleep "..SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time

      local response, status = http_client.get(PROXY_URL.."/get", {}, {host = "test8.com"})
      assert.are.equal(200, status)
      local body = cjson.decode(response)

      assert.are.equal("3", body.headers["X-Ratelimit-Remaining-Image"])
      assert.are.equal("4", body.headers["X-Ratelimit-Remaining-Video"])
    end)
  end)

  it("should block on first violation", function()
    local _, status = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "image=4, video=2"}, {host = "test7.com"})
    assert.are.equal(200, status)

    os.execute("sleep "..SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time

    local response, status = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=2"}, {host = "test7.com"})
    assert.are.equal(429, status)
    assert.are.equal("API rate limit exceeded for 'image'", cjson.decode(response).message)
  end)

  describe("Continue on error", function()
    after_each(function()
      dao_factory:drop_schema()
      prepare_db()
    end)

    it("should not continue if an error occurs", function()
      local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=1"}, {host = "test4.com"})
      assert.are.equal(200, status)
      assert.are.same('6', headers["x-ratelimit-limit-video-minute"])
      assert.are.same('5', headers["x-ratelimit-remaining-video-minute"])

      -- Simulate an error on the database
      local err = dao_factory.response_ratelimiting_metrics:drop_table(dao_factory.response_ratelimiting_metrics.table)
      assert.falsy(err)

      -- Make another request
      local res, status, _ = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=1"}, {host = "test4.com"})
      assert.equal("An unexpected error occurred", cjson.decode(res).message)
      assert.are.equal(500, status)
    end)

    it("should continue if an error occurs", function()
      local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=1"}, {host = "test5.com"})
      assert.are.equal(200, status)
      assert.falsy(headers["x-ratelimit-limit-video-minute"])
      assert.falsy(headers["x-ratelimit-remaining-video-minute"])

      -- Simulate an error on the database
      local err = dao_factory.response_ratelimiting_metrics:drop_table(dao_factory.response_ratelimiting_metrics.table)
      assert.falsy(err)

      -- Make another request
      local _, status, headers = http_client.get(PROXY_URL.."/response-headers", {["x-kong-limit"] = "video=1"}, {host = "test5.com"})
      assert.are.equal(200, status)
      assert.falsy(headers["x-ratelimit-limit-video-minute"])
      assert.falsy(headers["x-ratelimit-remaining-video-minute"])
    end)
  end)

end)
