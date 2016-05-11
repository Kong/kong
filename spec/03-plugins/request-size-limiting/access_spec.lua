local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local STUB_POST_URL = spec_helper.STUB_POST_URL

describe("RequestSizeLimiting Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests-request-size-limiting", request_host = "test3.com", upstream_url = "http://mockbin.com/request" }
      },
      plugin = {
        { name = "request-size-limiting", config = {allowed_payload_size = 10}, __api = 1 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("With request size less than allowed limit", function()
    it("should be allowed", function()
      local _, status = http_client.post(STUB_POST_URL, {key = "This is a test string"}, { host = "test3.com", ['Content-Length'] = "24", Expect = "100-continue", ['Content-Type'] = "application/x-www-form-urlencoded" } )
      assert.are.equal(200, status)
    end)
  end)

  describe("With request size greater than allowed limit", function()
    it("should get blocked", function()
      local _, status = http_client.post(STUB_POST_URL, {key = "This is a long test string"}, { host = "test3.com", ['Content-Length'] = "12000000", Expect = "100-continue", ['Content-Type'] = "application/x-www-form-urlencoded" } )
      assert.are.equal(417, status)
    end)
  end)

  describe("With request size greater than allowed limit but no expect header", function()
    it("should get blocked", function()
      local _, status = http_client.post(STUB_POST_URL, {key = "This is a long test string"}, { host = "test3.com", ['Content-Length'] = "12000000", ['Content-Type'] = "application/x-www-form-urlencoded" } )
      assert.are.equal(413, status)
    end)
  end)

  describe("With request size less than allowed limit but no expect header", function()
    it("should be allowed", function()
      local _, status = http_client.post(STUB_POST_URL, {key = "This is a test string"}, { host = "test3.com", ['Content-Length'] = "24", ['Content-Type'] = "application/x-www-form-urlencoded" } )
      assert.are.equal(200, status)
    end)
  end)

  describe("With no content-length header post request", function()
    it("should be allowed", function()
      local _, status = http_client.post(STUB_POST_URL, {key = "This is a test string"}, { host = "test3.com", ['Content-Type'] = "application/x-www-form-urlencoded" } )
      assert.are.equal(200, status)
    end)
  end)

  describe("With no content-length header get request", function()
    it("should be allowed", function()
      local _, status = http_client.get(STUB_POST_URL, {}, { host = "test3.com" } )
      assert.are.equal(200, status)
    end)
  end)

end)
