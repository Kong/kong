local cjson = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local constants = require "kong.constants"

local string_format = string.format

describe("Rate Limiting Consumer API", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests-rate-limiting-1", inbound_dns = "test-ratelimit1.com", upstream_url = "http://mockbin.com" }
      },
      consumer = {
        { custom_id = "provider_123" },
      },
      plugin = {
        { name = "key-auth", config = {key_names = {"apikey"}, hide_credentials = true}, __api = 1 },
        { name = "rate-limiting", config = { minute = 6, hour = 12 }, __api = 1 },
      },
      keyauth_credential = {
        { key = "apikey122", __consumer = 1 },
      }
    }
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Rate limit matrics usage", function()

    it("should return json with current rate limit matrics", function()

      -- make 2 requests to the api
      http_client.get(spec_helper.STUB_GET_URL, {}, {host = "test-ratelimit1.com", apikey = "apikey122"})
      http_client.get(spec_helper.STUB_GET_URL, {}, {host = "test-ratelimit1.com", apikey = "apikey122"})

      -- get current status
      local retrive_url = string_format("%s/apis/tests-rate-limiting-1/plugins/rate-limiting/usage/apikey122", spec_helper.CONSUMER_API_URL)
      local response_json, status = http_client.get(retrive_url, {})
      local response = cjson.decode(response_json)
      assert.are.equal(200, status)
      assert.are.equal(constants.RATELIMIT.USAGE.NO_LIMIT_VALUE, response.rate["limit-second"])
      assert.are.equal(constants.RATELIMIT.USAGE.NO_LIMIT_VALUE, response.rate["remaining-second"])

      assert.are.equal(6, response.rate["limit-minute"])
      assert.are.equal(4, response.rate["remaining-minute"])

      assert.are.equal(12, response.rate["limit-hour"])
      assert.are.equal(10, response.rate["remaining-hour"])

      assert.are.equal(constants.RATELIMIT.USAGE.NO_LIMIT_VALUE, response.rate["limit-day"])
      assert.are.equal(constants.RATELIMIT.USAGE.NO_LIMIT_VALUE, response.rate["remaining-day"])

      assert.are.equal(constants.RATELIMIT.USAGE.NO_LIMIT_VALUE, response.rate["limit-month"])
      assert.are.equal(constants.RATELIMIT.USAGE.NO_LIMIT_VALUE, response.rate["remaining-month"])

      assert.are.equal(constants.RATELIMIT.USAGE.NO_LIMIT_VALUE, response.rate["limit-year"])
      assert.are.equal(constants.RATELIMIT.USAGE.NO_LIMIT_VALUE, response.rate["remaining-year"])
    end)
  end)

  it("should return error - no consumer ", function()
    local retrive_url = string_format("%s/apis/tests-rate-limiting-1/plugins/rate-limiting/usage/invalid-api-key", spec_helper.CONSUMER_API_URL)
    local response_json, status = http_client.get(retrive_url, {})
    local response = cjson.decode(response_json)
    assert.are.equal(404, status)
    assert.are.equal("Not found", response.message)

  end)

end)
