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
        {name = "tests-response-transformer", request_host = "response.com", upstream_url = "http://httpbin.org"}
      },
      plugin = {
        {
          name = "response-transformer",
          config = {
            remove = {
              headers = {"Access-Control-Allow-Origin"},
              json = {"url"}
            }
          },
          __api = 1
        }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Test transforming parameters", function()
    it("should remove a parameter", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "response.com"})
      assert.equal(200, status)
      local body = cjson.decode(response)
      assert.falsy(body.url)
    end)
  end)
  
  describe("Test transforming headers", function()  
    it("should remove a header", function()
      local _, status, headers = http_client.get(STUB_HEADERS_URL, {}, {host = "response.com"})
      assert.equal(200, status)
      assert.falsy(headers["access-control-allow-origin"])
    end)
  end)
end)
