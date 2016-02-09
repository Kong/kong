local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local PROXY_URL = spec_helper.PROXY_URL

describe("Upstream", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { request_host = "upstream1.com", upstream_url = "http://mockbin.org" }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  
  it("should return JSON 500 error", function()
    print(http_client.get(PROXY_URL.."/status/503", {}, {host="upstream1.com"}))
  end)
  
end)
