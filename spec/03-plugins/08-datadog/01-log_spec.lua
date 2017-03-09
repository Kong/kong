local helpers = require "spec.helpers"
local threads = require "llthreads2.ex"

describe("Plugin: datadog (log)", function()
  local client
  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name = "datadog1_com",
      hosts = { "datadog1.com" },
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "datadog2_com",
      hosts = { "datadog2.com" },
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      name = "datadog3_com",
      hosts = { "datadog3.com" },
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.dao.plugins:insert {
      name = "datadog",
      api_id = api1.id,
      config = {
        host = "127.0.0.1",
        port = 9999,
        tags = {}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "datadog",
      api_id = api2.id,
      config = {
        host = "127.0.0.1",
        port = 9999,
        metrics = "request_count,status_count",
        tags = {}
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "datadog",
      api_id = api3.id,
      config = {
        host = "127.0.0.1",
        port = 9999,
        metrics = "request_count,status_count,latency",
        tags = {
          request_count = {"T1:V1"},
          status_count = {"T2:V2,T3:V3,T4"},
          latency = {"T2:V2:V3,T4"},
        }
      }
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
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
        for _ = 1, 6 do
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
    assert.equal(6, #gauges)
    assert.contains("kong.datadog1_com.request.count:1|c", gauges)
    assert.contains("kong.datadog1_com.latency:%d+|g", gauges, true)
    assert.contains("kong.datadog1_com.request.size:%d+|g", gauges, true)
    assert.contains("kong.datadog1_com.request.status.200:1|c", gauges)
    assert.contains("kong.datadog1_com.response.size:%d+|g", gauges, true)
    assert.contains("kong.datadog1_com.upstream_latency:%d+|g", gauges, true)
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
        for _ = 1, 2 do
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

  it("logs metrics with tags", function()
    local thread = threads.new({
      function()
        local socket = require "socket"
        local server = assert(socket.udp())
        server:settimeout(1)
        server:setoption("reuseaddr", true)
        server:setsockname("127.0.0.1", 9999)
        local gauges = {}
        for _ = 1, 3 do
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
        ["Host"] = "datadog3.com"
      }
    })
    assert.res_status(200, res)

    local ok, gauges = thread:join()
    assert.True(ok)
    assert.equal(3, #gauges)
    assert.contains("kong.datadog3_com.request.count:1|c|#T1:V1", gauges)
    assert.contains("kong.datadog3_com.request.status.200:1|c|#T2:V2,T3:V3,T4", gauges)
    assert.contains("kong.datadog3_com.latency:%d+|g|#T2:V2:V3,T4", gauges, true)
  end)
end)
