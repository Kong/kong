local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local ssl_fixtures = require "spec.plugins.ssl.fixtures"

describe("SSL Admin API", function()
  local BASE_URL

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
    spec_helper.insert_fixtures {
      api = {
        {name = "mockbin", request_host = "mockbin.com", upstream_url = "http://mockbin.com"}
      }
    }
    BASE_URL = spec_helper.API_URL.."/apis/mockbin/plugins/"
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/apis/:api/plugins", function()

    it("should refuse to set a `consumer_id` if asked to", function()
      local response, status = http_client.post_multipart(BASE_URL,
        {name = "ssl", consumer_id = "504b535e-dc1c-11e5-8554-b3852c1ec156", ["config.cert"] = ssl_fixtures.cert, ["config.key"] = ssl_fixtures.key}
      )
      assert.equal(400, status)
      local body = json.decode(response)
      assert.equal("No consumer can be configured for that plugin", body.message)
    end)

  end)
end)
