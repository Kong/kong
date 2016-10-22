local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Real IP proxying", function()
  local client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()

    assert(helpers.dao.apis:insert {
      name = "mockbin",
      request_path = "/mockbin",
      strip_request_path = true,
      upstream_url = "http://mockbin.com"
    })
  end)

  teardown(function()
    if client then client:close() end
    helpers.kill_all()
  end)

  it("X-Forwarded-* request headers", function()
    local res = assert(client:send {
      method = "GET",
      path = "/mockbin/request",
    })
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.matches("127.0.0.1", json.headers["x-forwarded-for"], nil, true)
    assert.equal("80", json.headers["x-forwarded-port"])
    assert.equal("http", json.headers["x-forwarded-proto"])
    assert.equal("127.0.0.1", json.clientIPAddress)
  end)
end)
