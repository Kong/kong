local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_POST_URL = spec_helper.PROXY_URL.."/post"

local function create_big_data(size)
  return string.format([[
    {"mock_json":{"big_field":"%s"}}
  ]], string.rep("*", size))
end

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
            add = {
              json = {"p1:v1"}
            },
            remove = {
              json = {"json"}
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
  
  describe("Test add", function()
    it("should add new parameters on GET", function()
      local response, status = http_client.post(STUB_POST_URL, {create_big_data(1 * 1024 * 1024)}, {host = "response.com", ["content-type"] = "application/json"})
      assert.equal(200, status)
      local body = cjson.decode(response)
      assert.equal("v1", body["p1"])
    end)
  end)
  
  describe("Test remove", function()
    it("should remove parameters on GET", function()
      local response, status = http_client.post(STUB_POST_URL, {create_big_data(1 * 1024 * 1024)}, {host = "response.com", ["content-type"] = "application/json"})
      assert.equal(200, status)
      local body = cjson.decode(response)
      assert.falsy(body["json"])
    end)
  end)
end)
