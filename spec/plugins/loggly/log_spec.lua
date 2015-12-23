local cjson = require "cjson"
local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local STUB_GET_URL = spec_helper.STUB_GET_URL

local UDP_PORT = spec_helper.find_port()

describe("Logging Plugins", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { request_host = "logging.com", upstream_url = "http://mockbin.com" },
        { request_host = "logging1.com", upstream_url = "http://mockbin.com" },
        { request_host = "logging2.com", upstream_url = "http://mockbin.com" },
        { request_host = "logging3.com", upstream_url = "http://mockbin.com" }
      },
      plugin = {
        { name = "loggly", config = { host = "127.0.0.1", port = UDP_PORT, key = "123456789", log_level = "info",
                                      successful_severity = "warning" }, __api = 1 },
        { name = "loggly", config = { host = "127.0.0.1", port = UDP_PORT, key = "123456789", log_level = "debug",
                                      successful_severity = "info", timeout = 2000 }, __api = 2 },
        { name = "loggly", config = { host = "127.0.0.1", port = UDP_PORT, key = "123456789", log_level = "crit",
                                      successful_severity = "crit", client_errors_severity = "warning" }, __api = 3 },
        { name = "loggly", config = { host = "127.0.0.1", port = UDP_PORT, key = "123456789" }, __api = 4 },
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should log to UDP when severity is warning and log level info", function()
    local thread = spec_helper.start_udp_server(UDP_PORT) -- Starting the mock TCP server

    local _, status = http_client.get(STUB_GET_URL, nil, { host = "logging.com" })
    assert.are.equal(200, status)

    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    local pri = string.sub(res,2,3)
    assert.are.equal("12", pri)

    local message = {}
    for w in string.gmatch(res,"{.*}") do
      table.insert(message, w)
    end
    local log_message = cjson.decode(message[1])
    assert.are.same("127.0.0.1", log_message.client_ip)
  end)

  it("should log to UDP when severity is info and log level debug", function()
    local thread = spec_helper.start_udp_server(UDP_PORT) -- Starting the mock TCP server

    local _, status = http_client.get(STUB_GET_URL, nil, { host = "logging1.com" })
    assert.are.equal(200, status)

    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    local pri = string.sub(res,2,3)
    assert.are.equal("14", pri)

    local message = {}
    for w in string.gmatch(res,"{.*}") do
      table.insert(message, w)
    end
    local log_message = cjson.decode(message[1])
    assert.are.same("127.0.0.1", log_message.client_ip)
  end)

  it("should log to UDP when severity is critical and log level critical", function()
    local thread = spec_helper.start_udp_server(UDP_PORT) -- Starting the mock TCP server

    local _, status = http_client.get(STUB_GET_URL, nil, { host = "logging2.com" })
    assert.are.equal(200, status)

    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    local pri = string.sub(res,2,3)
    assert.are.equal("10", pri)

    local message = {}
    for w in string.gmatch(res,"{.*}") do
      table.insert(message, w)
    end
    local log_message = cjson.decode(message[1])
    assert.are.same("127.0.0.1", log_message.client_ip)
  end)

  it("should log to UDP when severity and log level are default values", function()
    local thread = spec_helper.start_udp_server(UDP_PORT) -- Starting the mock TCP server

    local _, status = http_client.get(STUB_GET_URL, nil, { host = "logging3.com" })
    assert.are.equal(200, status)

    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    local pri = string.sub(res,2,3)
    assert.are.equal("14", pri)

    local message = {}
    for w in string.gmatch(res,"{.*}") do
      table.insert(message, w)
    end
    local log_message = cjson.decode(message[1])
    assert.are.same("127.0.0.1", log_message.client_ip)
  end)
end)
