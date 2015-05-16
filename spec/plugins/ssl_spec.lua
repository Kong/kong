local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

STUB_GET_SSL_URL = spec_helper.STUB_GET_SSL_URL

describe("SSL Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  it("should return invalid credentials when the credential value is wrong", function()
    local response, status, headers = http_client.get(STUB_GET_SSL_URL, { })
    print(response)
    assert.are.equal(200, status)
  end)

end)
