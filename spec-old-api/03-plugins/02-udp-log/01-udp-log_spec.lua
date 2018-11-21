local cjson = require "cjson"
local helpers = require "spec.helpers"

local UDP_PORT = 35001

describe("Plugin: udp-log (log)", function()
  local client

  lazy_setup(function()
    local _, db, dao = helpers.get_db_utils()

    local api1 = assert(dao.apis:insert {
      name         = "tests-udp-logging",
      hosts        = { "udp_logging.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(db.plugins:insert {
      api = { id = api1.id },
      name   = "udp-log",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT
      },
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    client = helpers.proxy_client()
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("logs proper latencies", function()
    local udp_thread = helpers.udp_server(UDP_PORT)

    -- Making the request
    local r = assert(client:send {
      method  = "GET",
      path    = "/delay/2",
      headers = {
        host = "udp_logging.com",
      },
    })

    assert.response(r).has.status(200)
    -- Getting back the UDP server input
    local ok, res = udp_thread:join()
    assert.True(ok)
    assert.is_string(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)

    assert.True(log_message.latencies.proxy < 3000)
    local is_latencies_sum_adding_up =
      1+log_message.latencies.request >= log_message.latencies.kong +
      log_message.latencies.proxy

    assert.True(is_latencies_sum_adding_up)
  end)

  it("logs to UDP", function()
    local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    -- Making the request
    local res = assert(client:send {
      method  = "GET",
      path    = "/request",
      headers = {
        host = "udp_logging.com",
      },
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
