local cjson = require "cjson"
local helpers = require "spec.helpers"

local TCP_PORT = 35002
local UDP_PORT = 35001
local HTTP_DELAY_PORT = 35004

describe("Plugin: udp-log (log)", function()
  local client

  setup(function()
    local api2 = assert(helpers.dao.apis:insert {
      name = "tests-udp-logging2",
      hosts = { "udp_logging2.com" },
      upstream_url = "http://127.0.0.1:"..HTTP_DELAY_PORT,
    })
    local api3 = assert(helpers.dao.apis:insert {
      name = "tests-udp-logging",
      hosts = { "udp_logging.com" },
      upstream_url = "http://mockbin.com",
    })

    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "udp-log",
      config = {
        host = "127.0.0.1",
        port = TCP_PORT
      },
    })
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "udp-log",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT
      },
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("logs proper latencies", function()
    local http_thread = helpers.http_server(HTTP_DELAY_PORT)
    local udp_thread = helpers.udp_server(TCP_PORT)

    -- Making the request
    local r = assert(client:send {
      method = "GET",
      path = "/request/delay",
      headers = {
        host = "udp_logging2.com"
      }
    })

    assert.response(r).has.status(200)
    -- Getting back the UDP server input
    local ok, res = udp_thread:join()
    assert.True(ok)
    assert.is_string(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)

    assert.True(log_message.latencies.proxy < 3000)
    assert.True(log_message.latencies.request >= log_message.latencies.kong + log_message.latencies.proxy)

    http_thread:join()
  end)

  it("logs to UDP", function()
    local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    -- Making the request
    local res = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "udp_logging.com"
      }
    })
    assert.response(res).has.status(200)

    -- Getting back the TCP server input
    local ok, res = thread:join()
    assert.True(ok)
    assert.is_string(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)
    assert.equal("127.0.0.1", log_message.client_ip)
  end)
end)
