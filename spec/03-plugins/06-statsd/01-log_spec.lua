local helpers  = require "spec.helpers"


local fmt = string.format


local UDP_PORT = 20000


for _, strategy in helpers.each_strategy() do
  describe("Plugin: statsd (log) [#" .. strategy .. "]", function()
    local proxy_client
    local proxy_client_grpc

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local consumer = bp.consumers:insert {
        username  = "bob",
        custom_id = "robert",
      }

      bp.keyauth_credentials:insert {
        key      = "kong",
        consumer = { id = consumer.id },
      }

      local routes = {}
      for i = 1, 13 do
        local service = bp.services:insert {
          protocol = helpers.mock_upstream_protocol,
          host     = helpers.mock_upstream_host,
          port     = helpers.mock_upstream_port,
          name     = fmt("statsd%s", i)
        }
        routes[i] = bp.routes:insert {
          hosts   = { fmt("logging%d.com", i) },
          service = service
        }
      end

      bp.key_auth_plugins:insert { route = { id = routes[1].id } }

      bp.statsd_plugins:insert {
        route = { id = routes[1].id },
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
        },
      }

      bp.statsd_plugins:insert {
        route = { id = routes[2].id },
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

      bp.statsd_plugins:insert {
        route = { id = routes[3].id },
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

      bp.statsd_plugins:insert {
        route = { id = routes[4].id },
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

      bp.statsd_plugins:insert {
        route = { id = routes[5].id },
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

      bp.statsd_plugins:insert {
        route = { id = routes[6].id },
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

      bp.statsd_plugins:insert {
        route = { id = routes[7].id },
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

      bp.statsd_plugins:insert {
        route = { id = routes[8].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[9].id } }

      bp.statsd_plugins:insert {
        route = { id = routes[9].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[10].id } }

      bp.statsd_plugins:insert {
        route = { id = routes[10].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[11].id } }

      bp.statsd_plugins:insert {
        route = { id = routes[11].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[12].id } }

      bp.statsd_plugins:insert {
        route = { id = routes[12].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[13].id } }

      bp.statsd_plugins:insert {
        route = { id = routes[13].id },
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          prefix   = "prefix",
        },
      }

      -- grpc
      local grpc_routes = {}
      for i = 1, 2 do
        local service = bp.services:insert {
          url = "grpc://localhost:15002",
          name     = fmt("grpc_statsd%s", i)
        }
        grpc_routes[i] = bp.routes:insert {
          hosts   = { fmt("grpc_logging%d.com", i) },
          service = service
        }
      end

      bp.statsd_plugins:insert {
        route = { id = grpc_routes[1].id },
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
        },
      }

      bp.statsd_plugins:insert {
        route = { id = grpc_routes[2].id },
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

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      proxy_client_grpc = helpers.proxy_client_grpc()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("metrics", function()
      it("logs over UDP with default metrics", function()
        local thread = helpers.udp_server(UDP_PORT, 12)
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
        assert.contains("kong.statsd1.request.count:1|c", metrics)
        assert.contains("kong.statsd1.latency:%d+|ms", metrics, true)
        assert.contains("kong.statsd1.request.size:110|ms", metrics)
        assert.contains("kong.statsd1.request.status.200:1|c", metrics)
        assert.contains("kong.statsd1.request.status.total:1|c", metrics)
        assert.contains("kong.statsd1.response.size:%d+|ms", metrics, true)
        assert.contains("kong.statsd1.upstream_latency:%d*|ms", metrics, true)
        assert.contains("kong.statsd1.kong_latency:%d*|ms", metrics, true)
        assert.contains("kong.statsd1.user.uniques:robert|s", metrics)
        assert.contains("kong.statsd1.user.robert.request.count:1|c", metrics)
        assert.contains("kong.statsd1.user.robert.request.status.total:1|c",
                        metrics)
        assert.contains("kong.statsd1.user.robert.request.status.200:1|c",
                        metrics)
      end)
      it("logs over UDP with default metrics and new prefix", function()
        local thread = helpers.udp_server(UDP_PORT, 12)
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
        assert.contains("prefix.statsd13.request.count:1|c", metrics)
        assert.contains("prefix.statsd13.latency:%d+|ms", metrics, true)
        assert.contains("prefix.statsd13.request.size:%d*|ms", metrics, true)
        assert.contains("prefix.statsd13.request.status.200:1|c", metrics)
        assert.contains("prefix.statsd13.request.status.total:1|c", metrics)
        assert.contains("prefix.statsd13.response.size:%d+|ms", metrics, true)
        assert.contains("prefix.statsd13.upstream_latency:%d*|ms", metrics, true)
        assert.contains("prefix.statsd13.kong_latency:%d*|ms", metrics, true)
        assert.contains("prefix.statsd13.user.uniques:robert|s", metrics)
        assert.contains("prefix.statsd13.user.robert.request.count:1|c", metrics)
        assert.contains("prefix.statsd13.user.robert.request.status.total:1|c",
                        metrics)
        assert.contains("prefix.statsd13.user.robert.request.status.200:1|c",
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
        assert.equal("kong.statsd5.request.count:1|c", res)
      end)
      it("status_count", function()
        local thread = helpers.udp_server(UDP_PORT, 2)
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
        assert.contains("kong.statsd3.request.status.200:1|c", res)
        assert.contains("kong.statsd3.request.status.total:1|c", res)
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
        assert.matches("kong.statsd4.request.size:%d+|ms", res)
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
        assert.matches("kong.statsd2.latency:.*|ms", res)
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
        assert.matches("kong.statsd6.response.size:%d+|ms", res)
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
        assert.matches("kong.statsd7.upstream_latency:.*|ms", res)
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
        assert.matches("kong.statsd8.kong_latency:.*|ms", res)
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
        assert.matches("kong.statsd9.user.uniques:robert|s", res)
      end)
      it("status_count_per_user", function()
        local thread = helpers.udp_server(UDP_PORT, 2)
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
        assert.contains("kong.statsd10.user.robert.request.status.200:1|c", res)
        assert.contains("kong.statsd10.user.robert.request.status.total:1|c", res)
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
        assert.matches("kong.statsd11.user.bob.request.count:1|c", res)
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
        assert.matches("kong%.statsd12%.latency:%d+|g", res)
      end)
    end)
    describe("metrics #grpc", function()
      it("logs over UDP with default metrics", function()
        local thread = helpers.udp_server(UDP_PORT, 8)

        local ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-authority"] = "grpc_logging1.com",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)

        local ok, metrics = thread:join()
        assert.True(ok)
        assert.contains("kong.grpc_statsd1.request.count:1|c", metrics)
        assert.contains("kong.grpc_statsd1.latency:%d+|ms", metrics, true)
        assert.contains("kong.grpc_statsd1.request.size:%d+|ms", metrics, true)
        assert.contains("kong.grpc_statsd1.request.status.200:1|c", metrics)
        assert.contains("kong.grpc_statsd1.request.status.total:1|c", metrics)
        assert.contains("kong.grpc_statsd1.response.size:%d+|ms", metrics, true)
        assert.contains("kong.grpc_statsd1.upstream_latency:%d*|ms", metrics, true)
        assert.contains("kong.grpc_statsd1.kong_latency:%d*|ms", metrics, true)
      end)
      it("latency as gauge", function()
        local thread = helpers.udp_server(UDP_PORT)

        local ok, resp = proxy_client_grpc({
          service = "hello.HelloService.SayHello",
          body = {
            greeting = "world!"
          },
          opts = {
            ["-authority"] = "grpc_logging2.com",
          }
        })
        assert.truthy(ok)
        assert.truthy(resp)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong%.grpc_statsd2%.latency:%d+|g", res)
      end)
    end)
  end)
end
