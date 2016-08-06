local helpers = require "spec.helpers"
local threads = require "llthreads2.ex"

describe("Plugin: datadog (log)", function()
  local client
  setup(function()
    assert(helpers.start_kong())
    client = helpers.proxy_client()

    local api1 = assert(helpers.dao.apis:insert {request_host = "datadog1.com", upstream_url = "http://mockbin.com"})
    local api2 = assert(helpers.dao.apis:insert {request_host = "datadog2.com", upstream_url = "http://mockbin.com"})

    assert(helpers.dao.plugins:insert {
      name = "datadog",
      api_id = api1.id,
      config = {
        host = "127.0.0.1",
        port = 9999
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "datadog",
      api_id = api2.id,
      config = {
        host = "127.0.0.1",
        port = 9999,
        metrics = "request_count,status_count"
      }
    })
  end)
  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("logs metrics over UDP", function()
    local thread = threads.new({
      function()
        local socket = require "socket"
        local server = assert(socket.udp())
        server:settimeout(1)
        server:setoption("reuseaddr", true)
        server:setsockname("127.0.0.1", 9999)
        local gauges = {}
        for i = 1, 5 do
          gauges[#gauges+1] = server:receive()
        end
        server:close()
        return gauges
      end
    })
    thread:start()

    local res = assert(client:send {
      method = "GET",
      path = "/status/200",
      headers = {
        ["Host"] = "datadog1.com"
      }
    })
    assert.res_status(200, res)

    local ok, gauges = thread:join()
    assert.True(ok)
    assert.equal(5, #gauges)
    assert.contains("kong.datadog1_com.request.count:1|c", gauges)
    assert.contains("kong.datadog1_com.latency:%d+|g", gauges, true)
    assert.contains("kong.datadog1_com.request.size:%d+|g", gauges, true)
    assert.contains("kong.datadog1_com.request.status.200:1|c", gauges)
    assert.contains("kong.datadog1_com.response.size:%d+|g", gauges, true)
  end)

  it("logs only given metrics", function()
    local thread = threads.new({
      function()
        local socket = require "socket"
        local server = assert(socket.udp())
        server:settimeout(1)
        server:setoption("reuseaddr", true)
        server:setsockname("127.0.0.1", 9999)
        local gauges = {}
        for i = 1, 2 do
          gauges[#gauges+1] = server:receive()
        end
        server:close()
        return gauges
      end
    })
    thread:start()

    local res = assert(client:send {
      method = "GET",
      path = "/status/200",
      headers = {
        ["Host"] = "datadog2.com"
      }
    })
    assert.res_status(200, res)

    local ok, gauges = thread:join()
    assert.True(ok)
    assert.equal(2, #gauges)
    assert.contains("kong.datadog2_com.request.count:1|c", gauges)
    assert.contains("kong.datadog2_com.request.status.200:1|c", gauges)
  end)
end)
