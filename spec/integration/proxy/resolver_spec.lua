local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL

describe("Resolver #proxy", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Invalid API", function()

    it("should return API not found when the API is missing", function()
      local response, status, headers = http_client.get(spec_helper.PROXY_URL)
      local body = cjson.decode(response)
      assert.are.equal(404, status)
      assert.are.equal("API not found", body.message)
    end)

  end)

  describe("Existing API", function()

    it("should return API found when the API has been created", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
      assert.are.equal(200, status)
    end)

  end)
end)
