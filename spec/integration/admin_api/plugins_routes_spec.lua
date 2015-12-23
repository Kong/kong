local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

describe("Admin API", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {request_host = "test.com", upstream_url = "http://mockbin.com"}
      }
    }
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/plugins/enabled", function()
    local BASE_URL = spec_helper.API_URL.."/plugins/enabled"

    it("should return a list of enabled plugins on this node", function()
      local response, status = http_client.get(BASE_URL)
      assert.equal(200, status)
      local body = json.decode(response)
      assert.equal("table", type(body.enabled_plugins))
    end)
  end)

  describe("/plugins/schema/:name", function()
    local BASE_URL = spec_helper.API_URL.."/plugins/schema/key-auth"

    it("[SUCCESS] should return the schema of a plugin", function()
      local response, status = http_client.get(BASE_URL)
      assert.equal(200, status)
      local body = json.decode(response)
      assert.equal("table", type(body.fields))
    end)

    it("[FAILURE] should return a descriptive error if schema is not found", function()
      local response, status = http_client.get(spec_helper.API_URL.."/plugins/schema/foo")
      assert.equal(404, status)
      local body = json.decode(response)
      assert.equal("No plugin named 'foo'", body.message)
    end)
  end)
end)
