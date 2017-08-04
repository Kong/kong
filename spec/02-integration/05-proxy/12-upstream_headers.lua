local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Upstream Headers", function()
  local client
  setup(function()
    assert(helpers.dao.apis:insert {
      name = "mockbin",
      hosts = { "test.com" },
      strip_uri = true,
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("X-Forwarded-* request headers", function()
    local res = assert(client:send {
      method = "GET",
      path = "/request",
      headers = { host = "test.com" }
    })
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.matches("test.com", json.headers["x-forwarded-host"])
  end)
end)
