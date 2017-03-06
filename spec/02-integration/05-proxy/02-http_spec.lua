local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("HTTP proxying", function()
  local client
  setup(function()
    assert(helpers.dao.apis:insert {
      name = "mockbin",
      uris = { "/mockbin" },
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

  local function make_request()
    local res = assert(client:send {
      method = "GET",
      path = "/mockbin/request?hello=world",
    })
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equal("world", json.queryString.hello)
  end

  it("proxies on HTTP port", function()
    make_request()
  end)

  it("proxies on HTTP port multiple times", function()
    for i = 1, 10 do 
      make_request()
    end
  end)
end)
