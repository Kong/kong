local client = require "resty.websocket.client"
local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Websockets", function()
  setup(function()
    assert(helpers.dao.apis:insert {
      name = "ws",
      uris = { "/ws" },
      strip_uri = true,
      upstream_url = "http://sockb.in"
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  local function make_request(uri)
    local wb = assert(client:new())
    assert(wb:connect(uri))
    assert(wb:send_text("testing Kong"))

    local data = assert(wb:recv_frame())
    assert.equal("testing Kong", cjson.decode(data).reqData)

    assert(wb:send_close())

    return true
  end

  it("works without Kong", function()
    assert(make_request("ws://sockb.in"))
  end)

  it("works with Kong", function()
    assert(make_request("ws://"..helpers.test_conf.proxy_ip..":"..helpers.test_conf.proxy_port.."/ws"))
  end)

  it("works with Kong under HTTPS", function()
    assert(make_request("wss://"..helpers.test_conf.proxy_ssl_ip..":"..helpers.test_conf.proxy_ssl_port.."/ws"))
  end)
end)
