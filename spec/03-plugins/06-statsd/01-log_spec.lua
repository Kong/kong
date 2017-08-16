local helpers = require "spec.helpers"
local UDP_PORT = 20000

describe("Plugin: statsd (log)", function()
  local client
  setup(function()
    helpers.run_migrations()

    local consumer1 = assert(helpers.dao.consumers:insert {
      username = "bob",
      custom_id = "robert"
    })
    assert(helpers.dao.keyauth_credentials:insert {
      key = "kong",
      consumer_id = consumer1.id
    })

    local api1 = assert(helpers.dao.apis:insert {
      name = "stastd1",
      hosts = { "logging1.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id
    })
    local api2 = assert(helpers.dao.apis:insert {
      name = "stastd2",
      hosts = { "logging2.com" },
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      name = "stastd3",
      hosts = { "logging3.com" },
      upstream_url = "http://mockbin.com"
    })
    local api4 = assert(helpers.dao.apis:insert {
      name = "stastd4",
      hosts = { "logging4.com" },
      upstream_url = "http://mockbin.com"
    })
    local api5 = assert(helpers.dao.apis:insert {
      name = "stastd5",
      hosts = { "logging5.com" },
      upstream_url = "http://mockbin.com"
    })
    local api6 = assert(helpers.dao.apis:insert {
      name = "stastd6",
      hosts = { "logging6.com" },
      upstream_url = "http://mockbin.com"
    })
    local api7 = assert(helpers.dao.apis:insert {
      name = "stastd7",
      hosts = { "logging7.com" },
      upstream_url = "http://mockbin.com"
    })
    local api8 = assert(helpers.dao.apis:insert {
      name = "stastd8",
      hosts = { "logging8.com" },
      upstream_url = "http://mockbin.com"
    })
    local api9 = assert(helpers.dao.apis:insert {
      name = "stastd9",
      hosts = { "logging9.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api9.id
    })
    local api10 = assert(helpers.dao.apis:insert {
      name = "stastd10",
      hosts = { "logging10.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api10.id
    })
    local api11 = assert(helpers.dao.apis:insert {
      name = "stastd11",
      hosts = { "logging11.com" },
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api11.id
    })

    local api12 = assert(helpers.dao.apis:insert {
      name = "stastd12",
      hosts = { "logging12.com" },
      upstream_url = "http://mockbin.com"
    })

    local api13 = assert(helpers.dao.apis:insert {
      name = "stastd13",
      hosts = { "logging13.com" },
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api12.id
    })

    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api13.id
    })

    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "latency",
          stat_type = "timer"
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "status_count",
          stat_type = "counter",
          sample_rate = 1
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api4.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "request_size",
          stat_type = "timer"
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api5.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "request_count",
          stat_type = "counter",
          sample_rate = 1
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api6.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "response_size",
          stat_type = "timer"
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api7.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "upstream_latency",
          stat_type = "timer"
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api8.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "kong_latency",
          stat_type = "timer"
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api9.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "unique_users",
          stat_type = "set",
          consumer_identifier = "custom_id"
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api10.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "status_count_per_user",
          stat_type = "counter",
          consumer_identifier = "custom_id",
          sample_rate = 1
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api11.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "request_per_user",
          stat_type = "counter",
          consumer_identifier = "username",
          sample_rate = 1
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api12.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        metrics = {{
          name = "latency",
          stat_type = "gauge",
          sample_rate = 1
        }}
      }
    })
    assert(helpers.dao.plugins:insert {
      api_id = api13.id,
      name = "statsd",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        prefix = "prefix"
      }
    })

    assert(helpers.start_kong())
    client = helpers.proxy_client()
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("metrics", function()
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
          for i = 1, 12 do
            metrics[#metrics+1] = server:receive()
          end
          server:close()
          return metrics
        end
      }, UDP_PORT)
      thread:start()

      local response = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          host = "logging1.com"
        }
      })
      assert.res_status(200, response)

      local ok, metrics = thread:join()
      assert.True(ok)
      assert.contains("kong.stastd1.request.count:1|c", metrics)
      assert.contains("kong.stastd1.latency:%d+|ms", metrics, true)
      assert.contains("kong.stastd1.request.size:110|ms", metrics)
      assert.contains("kong.stastd1.request.status.200:1|c", metrics)
      assert.contains("kong.stastd1.request.status.total:1|c", metrics)
      assert.contains("kong.stastd1.response.size:%d+|ms", metrics, true)
      assert.contains("kong.stastd1.upstream_latency:%d*|ms", metrics, true)
      assert.contains("kong.stastd1.kong_latency:%d*|ms", metrics, true)
      assert.contains("kong.stastd1.user.uniques:robert|s", metrics)
      assert.contains("kong.stastd1.user.robert.request.count:1|c", metrics)
      assert.contains("kong.stastd1.user.robert.request.status.total:1|c",
                      metrics)
      assert.contains("kong.stastd1.user.robert.request.status.200:1|c",
                      metrics)
    end)
    it("logs over UDP with default metrics and new prefix", function()
      local threads = require "llthreads2.ex"

      local thread = threads.new({
        function(port)
          local socket = require "socket"
          local server = assert(socket.udp())
          server:settimeout(1)
          server:setoption("reuseaddr", true)
          server:setsockname("127.0.0.1", port)
          local metrics = {}
          for i = 1, 12 do
            metrics[#metrics+1] = server:receive()
          end
          server:close()
          return metrics
        end
      }, UDP_PORT)
      thread:start()

      local response = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          host = "logging13.com"
        }
      })
      assert.res_status(200, response)
      local ok, metrics = thread:join()
      assert.True(ok)
      assert.contains("prefix.stastd13.request.count:1|c", metrics)
      assert.contains("prefix.stastd13.latency:%d+|ms", metrics, true)
      assert.contains("prefix.stastd13.request.size:%d*|ms", metrics, true)
      assert.contains("prefix.stastd13.request.status.200:1|c", metrics)
      assert.contains("prefix.stastd13.request.status.total:1|c", metrics)
      assert.contains("prefix.stastd13.response.size:%d+|ms", metrics, true)
      assert.contains("prefix.stastd13.upstream_latency:%d*|ms", metrics, true)
      assert.contains("prefix.stastd13.kong_latency:%d*|ms", metrics, true)
      assert.contains("prefix.stastd13.user.uniques:robert|s", metrics)
      assert.contains("prefix.stastd13.user.robert.request.count:1|c", metrics)
      assert.contains("prefix.stastd13.user.robert.request.status.total:1|c",
                      metrics)
      assert.contains("prefix.stastd13.user.robert.request.status.200:1|c",
                      metrics)
    end)
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
      assert.equal("kong.stastd5.request.count:1|c", res)
    end)
    it("status_count", function()
      local threads = require "llthreads2.ex"

      local thread = threads.new({
        function(port)
          local socket = require "socket"
          local server = assert(socket.udp())
          server:settimeout(1)
          server:setoption("reuseaddr", true)
          server:setsockname("127.0.0.1", port)
          local metrics = {}
          for i = 1, 2 do
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
          host = "logging3.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.contains("kong.stastd3.request.status.200:1|c", res)
      assert.contains("kong.stastd3.request.status.total:1|c", res)
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
      assert.matches("kong.stastd4.request.size:%d+|ms", res)
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
      assert.matches("kong.stastd2.latency:.*|ms", res)
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
      assert.matches("kong.stastd6.response.size:%d+|ms", res)
    end)
    it("upstream_latency", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging7.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("kong.stastd7.upstream_latency:.*|ms", res)
    end)
    it("kong_latency", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = "logging8.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("kong.stastd8.kong_latency:.*|ms", res)
    end)
    it("unique_users", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          host = "logging9.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("kong.stastd9.user.uniques:robert|s", res)
    end)
    it("status_count_per_user", function()
      local threads = require "llthreads2.ex"

      local thread = threads.new({
        function(port)
          local socket = require "socket"
          local server = assert(socket.udp())
          server:settimeout(1)
          server:setoption("reuseaddr", true)
          server:setsockname("127.0.0.1", port)
          local metrics = {}
          for i = 1, 2 do
            metrics[#metrics+1] = server:receive()
          end
          server:close()
          return metrics
        end
      }, UDP_PORT)
      thread:start()
      local response = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          host = "logging10.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.contains("kong.stastd10.user.robert.request.status.200:1|c", res)
      assert.contains("kong.stastd10.user.robert.request.status.total:1|c", res)
    end)
    it("request_per_user", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          host = "logging11.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("kong.stastd11.user.bob.request.count:1|c", res)
    end)
    it("latency as gauge", function()
      local thread = helpers.udp_server(UDP_PORT)
      local response = assert(client:send {
        method = "GET",
        path = "/request?apikey=kong",
        headers = {
          host = "logging12.com"
        }
      })
      assert.res_status(200, response)

      local ok, res = thread:join()
      assert.True(ok)
      assert.matches("kong%.stastd12%.latency:%d+|g", res)
    end)
  end)
end)
