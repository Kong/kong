local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.PROXY_URL.."/get"
local STUB_HEADERS_URL = spec_helper.PROXY_URL.."/response-headers"

describe("Response Transformer Plugin #proxy", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests response-transformer", request_host = "response.com", upstream_url = "http://httpbin.org" },
        { name = "tests response-transformer 2", request_host = "response2.com", upstream_url = "http://httpbin.org" },
      },
      plugin = {
        {
          name = "response-transformer",
          config = {
            add = {
              headers = {"x-added:true", "x-added2:true" },
              json = {"newjsonparam:newvalue"}
            },
            remove = {
              headers = { "x-to-remove" },
              json = { "origin" }
            }
          },
          __api = 1
        },
        {
          name = "response-transformer",
          config = {
            add = {
              headers = {"Cache-Control:max-age=86400"}
            }
          },
          __api = 2
        }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Test adding parameters", function()

    it("should add new headers", function()
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "response.com"})
      assert.are.equal(200, status)
      assert.are.equal("true", headers["x-added"])
      assert.are.equal("true", headers["x-added2"])
    end)

    it("should add new parameters on GET", function()
      local response, status = http_client.get("http://127.0.0.1:8100/get", {}, {host = "response.com"})
      assert.are.equal(200, status)
      local body = cjson.decode(response)
      assert.are.equal("newvalue", body["newjsonparam"])
    end)

    it("should add new parameters on POST", function()
      local response, status = http_client.post("http://127.0.0.1:8100/post", {}, {host = "response.com"})
      assert.are.equal(200, status)
      local body = cjson.decode(response)
      assert.are.equal("newvalue", body["newjsonparam"])
    end)

    it("should add new headers", function()
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "response2.com"})
      assert.are.equal(200, status)
      assert.are.equal("max-age=86400", headers["cache-control"])
    end)

  end)

  describe("Test removing parameters", function()

    it("should remove a header", function()
      local _, status, headers = http_client.get(STUB_HEADERS_URL, { ["x-to-remove"] = "true"}, {host = "response.com"})
      assert.are.equal(200, status)
      assert.falsy(headers["x-to-remove"])
    end)

    it("should remove a parameter on GET", function()
      local response, status = http_client.get("http://127.0.0.1:8100/get", {}, {host = "response.com"})
      assert.are.equal(200, status)
      local body = cjson.decode(response)
      assert.falsy(body.origin)
    end)

  end)

end)
