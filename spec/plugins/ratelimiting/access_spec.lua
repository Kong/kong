local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local constants = require "kong.constants"

local string_format = string.format

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
        { name = "tests ratelimiting 2", public_dns = "test4.com", target_url = "http://mockbin.com" },
        { name = "tests ratelimiting 3", public_dns = "test5.com", target_url = "http://mockbin.com" },
        { name = "tests ratelimiting 4", public_dns = "test6.com", target_url = "http://mockbin.com" },
        { name = "tests ratelimiting 5", public_dns = "test7.com", target_url = "http://mockbin.com" }
      },
      consumer = {
        { custom_id = "provider_123" },
        { custom_id = "provider_124" }
      },
      plugin_configuration = {
        { name = "keyauth", value = {key_names = {"apikey"}, hide_credentials = true}, __api = 1 },
        { name = "ratelimiting", value = { minute = 6 }, __api = 1 },
        { name = "ratelimiting", value = { minute = 8 }, __api = 1, __consumer = 1 },
        { name = "ratelimiting", value = { minute = 6 }, __api = 2 },
        { name = "ratelimiting", value = { minute = 3, hour = 5 }, __api = 3 },
        { name = "ratelimiting", value = { minute = 33 }, __api = 4 },
        { name = "ratelimiting", value = { minute = 12, hour = 16 }, __api = 5 },
        
      },
      keyauth_credential = {
        { key = "apikey122", __consumer = 1 },
        { key = "apikey123", __consumer = 2 },

      }
    }

    -- Updating API test6.com with old plugin value, to check retrocompatibility
    local dao_factory = spec_helper.get_env().dao_factory
    -- Find API
    local res, err = dao_factory.apis:find_by_keys({public_dns = 'test6.com'})
    if err then error(err) end
    -- Find Plugin Configuration
    local res, err = dao_factory.plugins_configurations:find_by_keys({api_id = res[1].id})
    if err then error(err) end
    -- Set old value
    local plugin_configuration = res[1]
    plugin_configuration.value = {
      period = "minute",
      limit = 6
    }
    -- Update plugin configuration
    local _, err = dao_factory.plugins_configurations:execute(
      "update plugins_configurations SET value = '{\"limit\":6, \"period\":\"minute\"}' WHERE id = "..plugin_configuration.id.." and name = 'ratelimiting'")
    if err then error(err) end

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

      wait()

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

    describe("Old plugin format", function()     

      it("should get blocked if exceeding limit", function()
        wait()
        
        -- Default ratelimiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local _, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test6.com"})
          assert.are.equal(200, status)
          assert.are.same(tostring(limit), headers["x-ratelimit-limit"])
          assert.are.same(tostring(limit - i), headers["x-ratelimit-remaining"])
        end

        -- Third query, while limit is 2/minute
        local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test6.com"})
        local body = cjson.decode(response)
        assert.are.equal(429, status)
        assert.are.equal("API rate limit exceeded", body.message)
      end)

    end)
    
    describe("Default plugin", function()

      it("should get blocked if exceeding limit", function()
        wait()
        
        -- Default ratelimiting plugin for this API says 6/minute
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
        wait()

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

  describe("Rate limit matrics", function()
    it("should return json with current rate limit matrics", function()
      -- set matrics for second.
      local get_matrics_url = string_format("%s%s", spec_helper.PROXY_URL, constants.RATELIMIT.RETRIVE_METRICS.URI)

      -- make 2 requests to the api
      local response_json, status = http_client.get(STUB_GET_URL, {}, {host = "test7.com"})
      local response_json, status = http_client.get(STUB_GET_URL, {}, {host = "test7.com"})

      -- get current status
      local response_json, status = http_client.get(get_matrics_url, {}, {host = "test7.com"})
      local response = cjson.decode(response_json)

      assert.are.equal(constants.RATELIMIT.RETRIVE_METRICS.NO_LIMIT_VALUE, response.rate["limit-second"])
      assert.are.equal(constants.RATELIMIT.RETRIVE_METRICS.NO_LIMIT_VALUE, response.rate["remaining-second"])

      assert.are.equal(12, response.rate["limit-minute"])
      assert.are.equal(10, response.rate["remaining-minute"])

      assert.are.equal(16, response.rate["limit-hour"])
      assert.are.equal(14, response.rate["remaining-hour"])

      assert.are.equal(constants.RATELIMIT.RETRIVE_METRICS.NO_LIMIT_VALUE, response.rate["limit-day"])
      assert.are.equal(constants.RATELIMIT.RETRIVE_METRICS.NO_LIMIT_VALUE, response.rate["remaining-day"])

      assert.are.equal(constants.RATELIMIT.RETRIVE_METRICS.NO_LIMIT_VALUE, response.rate["limit-month"])
      assert.are.equal(constants.RATELIMIT.RETRIVE_METRICS.NO_LIMIT_VALUE, response.rate["remaining-month"])

    end)
  end)

end)
