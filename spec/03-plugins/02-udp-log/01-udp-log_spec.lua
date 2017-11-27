local cjson = require "cjson"
local helpers = require "spec.helpers"

local UDP_PORT = 35001

describe("Plugin: udp-log (log)", function()
  local client

  setup(function()
    helpers.run_migrations()

    local api1 = assert(helpers.dao.apis:insert {
      name         = "tests-udp-logging",
      hosts        = { "udp_logging.com" },
      upstream_url = helpers.mock_upstream_url
    })

    local api2 = assert(helpers.dao.apis:insert {
      name         = "tests-udp-logging-body-logs-100-bytes",
      hosts        = { "udp_logging_128_bytes_body.com" },
      upstream_url = helpers.mock_upstream_url
    })

    local api3 = assert(helpers.dao.apis:insert {
      name         = "tests-udp-logging-body-logs-default",
      hosts        = { "udp_logging_default_body_size.com" },
      upstream_url = helpers.mock_upstream_url
    })

    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name   = "udp-log",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name   = "udp-log",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        log_body = true,
        max_body_size = 128
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name   = "udp-log",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        log_body = true
      }
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    client = helpers.proxy_client()
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("logs proper latencies", function()
    local udp_thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

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
    assert.True(log_message.latencies.request >= log_message.latencies.kong + log_message.latencies.proxy)
  end)

  it("logs to UDP", function()
    local udp_thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    -- Making the request
    local r = assert(client:send {
      method  = "GET",
      path    = "/request",
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
    assert.equal("127.0.0.1", log_message.client_ip)
  end)

  it("does not log req/resp body if not configured to", function()
    local udp_thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

    -- Making the request
    local r = assert(client:send {
      method  = "POST",
      path    = "/request",
      headers = {
        host = "udp_logging.com",
      },
      body = string.rep("a", 32*1024)
    })
    assert.response(r).has.status(200)

    -- Getting back the UDP server input
    local ok, res = udp_thread:join()
    assert.True(ok)
    assert.is_string(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)
    
    assert.is_nil(log_message.request.body)
    assert.is_nil(log_message.response.body)

  end)

  it("should log whole request body if it less then maximum body size", function()
    local udp_thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server
    
    local max_expected_body_size = 64*1024;
    local sent_payload = "This is payload which should not be truncated"
    -- Making the request
    local r = assert(client:send {
      method  = "POST",
      path    = "/request",
      headers = {
        host = "udp_logging_default_body_size.com",
      },
      body = sent_payload
    })
    assert.response(r).has.status(200)

    -- Getting back the UDP server input
    local ok, res = udp_thread:join()
    assert.True(ok)
    assert.is_string(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)
    assert.equal(log_message.request.body, sent_payload); 
    assert.True(log_message.response.body:len() <= max_expected_body_size);
  end)

  it("logs request and response bodies with custom body size", function()
    local udp_thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server
    
    local max_expected_body_size = 128;
    -- Making the request
    local r = assert(client:send {
      method  = "POST",
      path    = "/request",
      headers = {
        host = "udp_logging_128_bytes_body.com",
      },
      body = string.rep("a", 32*1024)
    })
    assert.response(r).has.status(200)

    -- Getting back the UDP server input
    local ok, res = udp_thread:join()
    assert.True(ok)
    assert.is_string(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)
    assert.equal(log_message.request.body, string.rep("a", max_expected_body_size));
    assert.True(log_message.response.body:len() <= max_expected_body_size) ;
  end)
end)
