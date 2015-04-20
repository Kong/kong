local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

STUB_GET_URL = spec_helper.STUB_GET_URL
STUB_POST_URL = spec_helper.STUB_POST_URL

describe("Request Transformer Plugin #proxy", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Test headers", function()

    it("should add new headers", function()
      local response, status, headers = http_client.get(STUB_GET_URL, {host = "test7.com"})
      local body = cjson.decode(response)
      assert.are.equal(200, status)
      assert.are.equal("Your authentication credentials are invalid", body.message)
    end)

  end)

end)
