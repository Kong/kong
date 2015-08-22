local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local PROXY_URL = spec_helper.PROXY_URL
local SLEEP_VALUE = "0.5"

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
        { name = "tests response-ratelimiting 1", public_dns = "test1.com", target_url = "http://httpbin.org/" },
        { name = "tests response-ratelimiting 2", public_dns = "test2.com", target_url = "http://httpbin.org/" },
        { name = "tests response-ratelimiting 3", public_dns = "test3.com", target_url = "http://httpbin.org/" }
      },
      consumer = {
        { custom_id = "consumer_123" },
        { custom_id = "consumer_124" },
        { custom_id = "consumer_125" }
      },
      plugin_configuration = {
        { name = "response-ratelimiting", value = { limits = { video = { minute = 6 } } }, __api = 1 },
        { name = "response-ratelimiting", value = { limits = { video = { minute = 6, hour = 10 }, image = { minute = 4 } } }, __api = 2 },
        { name = "keyauth", value = {key_names = {"apikey"}, hide_credentials = true}, __api = 3 },
        { name = "response-ratelimiting", value = { limits = { video = { minute = 6 } } }, __api = 3 },
        { name = "response-ratelimiting", value = { limits = { video = { minute = 2 } } }, __api = 3, __consumer = 1 }
      },
      keyauth_credential = {
        { key = "apikey123", __consumer = 1 },
        { key = "apikey124", __consumer = 2 },
        { key = "apikey125", __consumer = 3 }
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
      wait()

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
        wait()
        
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
        wait()
        
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
        wait()
        
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

end)
