local helpers = require "spec.helpers"
local UDP_PORT = 20000

describe("Plugin: statsd (log)", function()
  local client
  setup(function()
    helpers.kill_all()
    helpers.prepare_prefix()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "logging1.com",
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      request_host = "logging2.com",
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      request_host = "logging3.com",
      upstream_url = "http://mockbin.com"
    })
    local api4 = assert(helpers.dao.apis:insert {
      request_host = "logging4.com",
      upstream_url = "http://mockbin.com"
    })
    local api5 = assert(helpers.dao.apis:insert {
      request_host = "logging5.com",
      upstream_url = "http://mockbin.com"
    })
    local api6 = assert(helpers.dao.apis:insert {
      request_host = "logging6.com",
      upstream_url = "http://mockbin.com"
    })

    -- plugin 1
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT
      }
    })
    -- plugin 2
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {"latency"}
      }
    })
    -- plugin 3
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {"status_count"}
      }
    })
    -- plugin 4
    assert(helpers.dao.plugins:insert {
      api_id = api4.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {"request_size"}
      }
    })
    -- plugin 5
    assert(helpers.dao.plugins:insert {
      api_id = api5.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {"request_count"}
      }
    })
    -- plugin 6
    assert(helpers.dao.plugins:insert {
      api_id = api6.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {"response_size"}
      }
    })

    assert(helpers.start_kong())
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("logs over UDP with default metrics", function()
    local threads = require "llthreads2.ex"

    local thread = threads.new({
      function(port)
        local socket = require "socket"
        local server = assert(socket.udp())
        server:settimeout(1)
        server:setoption("reuseaddr", true)
        server:setsockname("127.0.0.1", port)
        local metrics = {}
        for i = 1, 7 do
          metrics[#metrics+1] = server:receive()
        end
        server:close()
        return metrics
      end
    }, UDP_PORT)
    thread:start()

    local response = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = "logging1.com"
      }
    })
    assert.res_status(200, response)

    local ok, metrics = thread:join()
    assert.True(ok)
    assert.contains("kong.logging1_com.request.count:1|c", metrics)
    assert.contains("kong%.logging1_com%.latency:%d+|g", metrics, true)
    assert.contains("kong.logging1_com.request.size:98|g", metrics)
    assert.contains("kong.logging1_com.request.status.200:1|c", metrics)
    assert.contains("kong%.logging1_com%.response%.size:%d+|g", metrics, true)
  end)

  describe("metrics", function()
    it("request_count", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging5.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.equal("kong.logging5_com.request.count:1|c", res)
    end)
    it("status_count", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging3.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.equal("kong.logging3_com.request.status.200:1|c", res)
    end)
    it("request_size", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging4.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("kong.logging4_com.request.size:%d+|g", res)
    end)
    it("latency", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging2.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("kong.logging2_com.latency:.*|g", res)
    end)
    it("response_size", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging6.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("kong.logging6_com.response.size:%d+|g", res)
    end)
  end)
end)
