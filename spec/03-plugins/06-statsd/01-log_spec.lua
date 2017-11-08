local helpers  = require "spec.helpers"


local UDP_PORT = 20000


for _, strategy in helpers.each_strategy() do
  pending("Plugin: statsd (log) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local consumer = bp.consumers:insert {
        username  = "bob",
        custom_id = "robert",
      }

      bp.keyauth_credentials:insert {
        key         = "kong",
        consumer_id = consumer.id,
      }

      local route1 = bp.routes:insert {
        hosts = { "logging1.com" },
      }

      local route2 = bp.routes:insert {
        hosts = { "logging2.com" },
      }

      local route3 = bp.routes:insert {
        hosts = { "logging3.com" },
      }

      local route4 = bp.routes:insert {
        hosts = { "logging4.com" },
      }

      local route5 = bp.routes:insert {
        hosts = { "logging5.com" },
      }

      local route6 = bp.routes:insert {
        hosts = { "logging6.com" },
      }

      local route7 = bp.routes:insert {
        hosts = { "logging7.com" },
      }

      local route8 = bp.routes:insert {
        hosts = { "logging8.com" },
      }

      local route9 = bp.routes:insert {
        hosts = { "logging9.com" },
      }

      local route10 = bp.routes:insert {
        hosts = { "logging10.com" },
      }

      local route11 = bp.routes:insert {
        hosts = { "logging11.com" },
      }

      local route12 = bp.routes:insert {
        hosts = { "logging12.com" },
      }

      local route13 = bp.routes:insert {
        hosts = { "logging13.com" },
      }

      bp.plugins:insert {
        name       = "key-auth",
        route_id   = route1.id,
      }

      bp.plugins:insert {
        route_id   = route1.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
        },
      }

      bp.plugins:insert {
        route_id   = route2.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name      = "latency",
              stat_type = "timer"
            }
          },
        },
      }

      bp.plugins:insert {
        route_id   = route3.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name        = "status_count",
              stat_type   = "counter",
              sample_rate = 1,
            }
          },
        },
      }

      bp.plugins:insert {
        route_id   = route4.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name      = "request_size",
              stat_type = "timer",
            }
          },
        },
      }

      bp.plugins:insert {
        route_id   = route5.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name        = "request_count",
              stat_type   = "counter",
              sample_rate = 1,
            }
          }
        }
      }

      bp.plugins:insert {
        route_id   = route6.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name      = "response_size",
              stat_type = "timer",
            }
          },
        },
      }

      bp.plugins:insert {
        route_id   = route7.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name      = "upstream_latency",
              stat_type = "timer",
            }
          },
        },
      }

      bp.plugins:insert {
        route_id   = route8.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name      = "kong_latency",
              stat_type = "timer",
            }
          },
        }
      }

      bp.plugins:insert {
        name       = "key-auth",
        route_id   = route9.id,
      }

      bp.plugins:insert {
        route_id   = route9.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "unique_users",
              stat_type           = "set",
              consumer_identifier = "custom_id",
            }
          },
        },
      }

      bp.plugins:insert {
        name       = "key-auth",
        route_id   = route10.id,
      }

      bp.plugins:insert {
        route_id   = route10.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "status_count_per_user",
              stat_type           = "counter",
              consumer_identifier = "custom_id",
              sample_rate         = 1,
            }
          },
        },
      }

      bp.plugins:insert {
        name       = "key-auth",
        route_id   = route11.id,
      }

      bp.plugins:insert {
        route_id   = route11.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_per_user",
              stat_type           = "counter",
              consumer_identifier = "username",
              sample_rate         = 1,
            }
          },
        },
      }

      bp.plugins:insert {
        name       = "key-auth",
        route_id   = route12.id,
      }

      bp.plugins:insert {
        route_id   = route12.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name        = "latency",
              stat_type   = "gauge",
              sample_rate = 1,
            }
          },
        },
      }

      bp.plugins:insert {
        name       = "key-auth",
        route_id   = route13.id,
      }

      bp.plugins:insert {
        route_id   = route13.id,
        name       = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          prefix   = "prefix",
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    teardown(function()
      if proxy_client then
        proxy_client:close()
      end

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

        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging1.com"
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

        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging13.com"
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
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "logging5.com"
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
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "logging3.com"
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
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "logging4.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong.stastd4.request.size:%d+|ms", res)
      end)
      it("latency", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "logging2.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong.stastd2.latency:.*|ms", res)
      end)
      it("response_size", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "logging6.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong.stastd6.response.size:%d+|ms", res)
      end)
      it("upstream_latency", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "logging7.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong.stastd7.upstream_latency:.*|ms", res)
      end)
      it("kong_latency", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "logging8.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong.stastd8.kong_latency:.*|ms", res)
      end)
      it("unique_users", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
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
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging10.com"
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
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging11.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong.stastd11.user.bob.request.count:1|c", res)
      end)
      it("latency as gauge", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging12.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong%.stastd12%.latency:%d+|g", res)
      end)
    end)
  end)
end
