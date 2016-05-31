local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

local BASE_URL = spec_helper.API_URL.."/apis/%s/plugins/"

describe("Response Rate Limiting API", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests-response-ratelimiting1", request_host = "test1.com", upstream_url = "http://mockbin.com" }
      }
    }
    spec_helper.start_kong()

    local response = http_client.get(spec_helper.API_URL.."/apis/")
    BASE_URL = string.format(BASE_URL, json.decode(response).data[1].id)
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("POST", function()

    it("should not save with empty config", function()
      local response, status = http_client.post(BASE_URL, { name = "response-ratelimiting" })
      local body = json.decode(response)
      assert.are.equal(400, status)
      assert.are.equal("You need to set at least one limit name", body.config)
    end)

    it("should save with proper config", function()
      local response, status = http_client.post(BASE_URL, { name = "response-ratelimiting", ["config.limits.video.second"] = 10 })
      local body = json.decode(response)
      assert.are.equal(201, status)
      assert.are.equal(10, body.config.limits.video.second)
    end)

  end)

end)
