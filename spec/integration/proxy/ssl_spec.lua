local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL

describe("SSL PORT", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  it("should work when calling SSL port", function()
    local response, status = http_client.get(STUB_GET_SSL_URL, nil, { host = "test4.com" })
    assert.are.equal(200, status)
  end)

end)
