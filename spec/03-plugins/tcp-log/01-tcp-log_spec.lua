local cjson = require "cjson"
local helpers = require "spec.helpers"

local TCP_PORT = 35000
local HTTP_DELAY_PORT = 35003

describe("Plugin: tcp (log)", function()

  local client
  
  setup(function()
    helpers.kill_all()
    helpers.prepare_prefix()

    local api1 = assert(helpers.dao.apis:insert {
      name = "tests-tcp-logging", 
      request_host = "tcp_logging.com", 
      upstream_url = "http://mockbin.com",
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "tests-tcp-logging2", 
      request_host = "tcp_logging2.com", 
      upstream_url = "http://127.0.0.1:"..HTTP_DELAY_PORT,
    })

    -- plugin 1
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "tcp-log", 
      config = {
        host = "127.0.0.1", 
        port = TCP_PORT
      },
    })
    -- plugin 2
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "tcp-log", 
      config = {
        host = "127.0.0.1", 
        port = TCP_PORT
      },
    })

    assert(helpers.start_kong())
    client = assert(helpers.proxy_client())
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("logs to TCP", function()
    local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

    -- Making the request
    local r = assert(client:send {
      method = "GET",
      path = "/request", 
      headers = { 
        host = "tcp_logging.com"
      },
    })
    assert.response(r).has.status(200)

    -- Getting back the TCP server input
    local ok, res = thread:join()
    assert.is_true(ok)
    assert.is.string(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)
    assert.same("127.0.0.1", log_message.client_ip)
  end)

  it("logs proper latencies", function()
    local http_thread = helpers.http_server(HTTP_DELAY_PORT) -- Starting the mock TCP server
    local tcp_thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

    -- Making the request
    local r = assert(client:send {
      method = "GET",
      path = "/request/delay",
      headers = { 
        host = "tcp_logging2.com" 
      }
    })

    assert.response(r).has.status(200)
    -- Getting back the TCP server input
    local ok, res = tcp_thread:join()
    assert.is_true(ok)
    assert.is.string(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)

    assert.truthy(log_message.latencies.proxy < 3000)
    assert.truthy(log_message.latencies.request >= log_message.latencies.kong + log_message.latencies.proxy)

    http_thread:join()
  end)

end)
