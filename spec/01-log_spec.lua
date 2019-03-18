local helpers       = require "spec.helpers"


local fmt = string.format


local UDP_PORT = 20000


local uuid_pattern = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"


-- All tests that test the of all metrics from statsd CE go here


for _, strategy in helpers.each_strategy() do
  describe("Plugin: statsd-advanced (log) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy, nil, { "statsd-advanced" })

      local consumer = bp.consumers:insert {
        username  = "bob",
        custom_id = "robert",
      }

      bp.keyauth_credentials:insert {
        key         = "kong",
        consumer    = { id = consumer.id },
      }

      local routes = {}
      for i = 1, 14 do
        local service = bp.services:insert {
          protocol = helpers.mock_upstream_protocol,
          host     = helpers.mock_upstream_host,
          port     = helpers.mock_upstream_port,
          name     = fmt("statsdadvanced%s", i)
        }
        routes[i] = bp.routes:insert {
          hosts   = { fmt("logging%d.com", i) },
          service = service
        }
      end

      bp.key_auth_plugins:insert { route = { id = routes[1].id } }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route      = { id = routes[1].id },
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
        },
      }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route      = { id = routes[2].id },
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
        name     = "statsd-advanced",
        route      = { id = routes[3].id },
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
        name     = "statsd-advanced",
        route      = { id = routes[4].id },
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
        name     = "statsd-advanced",
        route      = { id = routes[5].id },
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
        name     = "statsd-advanced",
        route      = { id = routes[6].id },
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
        name     = "statsd-advanced",
        route      = { id = routes[7].id },
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
        name     = "statsd-advanced",
        route      = { id = routes[8].id },
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

      bp.plugins:insert {
        name     = "statsd-advanced",
        route      = { id = routes[9].id },
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

      bp.plugins:insert {
        name     = "statsd-advanced",
        route      = { id = routes[10].id },
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

      bp.plugins:insert {
        name     = "statsd-advanced",
        route      = { id = routes[11].id },
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

      bp.plugins:insert {
        name     = "statsd-advanced",
        route      = { id = routes[12].id },
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

      bp.plugins:insert {
        name     = "statsd-advanced",
        route      = { id = routes[13].id },
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          prefix   = "prefix",
        },
      }

      bp.key_auth_plugins:insert { route = { id = routes[14].id } }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route      = { id = routes[14].id },
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "unique_users",
              stat_type           = "set",
              consumer_identifier = "consumer_id",
            }
          },
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        -- this is to ensure we have the right number of shdicts being used so we know
        -- how many udp packets are we expecting below
        nginx_conf = "spec/fixtures/custom_nginx_statsd_advanced.template",
        plugins = "bundled,statsd-advanced",
        vitals = "off"
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
        local metrics_count = 12
        -- shdict_usage metrics
        metrics_count = metrics_count + (strategy == "cassandra" and 16 or 15) * 2

        local thread = helpers.udp_server(UDP_PORT, metrics_count)
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
        assert.contains("kong.service.statsdadvanced1.request.count:1|c", metrics)
        assert.contains("kong.service.statsdadvanced1.latency:%d+|ms", metrics, true)
        assert.contains("kong.service.statsdadvanced1.request.size:110|ms", metrics)
        assert.contains("kong.service.statsdadvanced1.status.200:1|c", metrics)
        assert.contains("kong.service.statsdadvanced1.response.size:%d+|ms", metrics, true)
        assert.contains("kong.service.statsdadvanced1.upstream_latency:%d*|ms", metrics, true)
        assert.contains("kong.service.statsdadvanced1.kong_latency:%d*|ms", metrics, true)
        assert.contains("kong.service.statsdadvanced1.user.uniques:robert|s", metrics)
        assert.contains("kong.service.statsdadvanced1.user.robert.request.count:1|c", metrics)
        assert.contains("kong.service.statsdadvanced1.user.robert.status.200:1|c",
                        metrics)
        assert.contains("kong.service.statsdadvanced1.workspace." .. uuid_pattern .. ".status.200:1|c",
                        metrics, true)
        assert.contains("kong.route." .. uuid_pattern .. ".user.robert.status.200:1|c", metrics, true)
        
        -- shdict_usage metrics, just test one is enough
        assert.contains("kong.node..*.shdict.kong.capacity:%d+|g", metrics, true)
        assert.contains("kong.node..*.shdict.kong.free_space:%d+|g", metrics, true)
      end)
      it("logs over UDP with default metrics and new prefix", function()
        local metrics_count = 12
        -- shdict_usage metrics, can't test again in 1 minutes
        -- metrics_count = metrics_count + (strategy == "cassandra" and 16 or 15) * 2

        local thread = helpers.udp_server(UDP_PORT, metrics_count)
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
        assert.contains("prefix.service.statsdadvanced13.request.count:1|c", metrics)
        assert.contains("prefix.service.statsdadvanced13.latency:%d+|ms", metrics, true)
        assert.contains("prefix.service.statsdadvanced13.request.size:111|ms", metrics)
        assert.contains("prefix.service.statsdadvanced13.status.200:1|c", metrics)
        assert.contains("prefix.service.statsdadvanced13.response.size:%d+|ms", metrics, true)
        assert.contains("prefix.service.statsdadvanced13.upstream_latency:%d*|ms", metrics, true)
        assert.contains("prefix.service.statsdadvanced13.kong_latency:%d*|ms", metrics, true)
        assert.contains("prefix.service.statsdadvanced13.user.uniques:robert|s", metrics)
        assert.contains("prefix.service.statsdadvanced13.user.robert.request.count:1|c", metrics)
        assert.contains("prefix.service.statsdadvanced13.user.robert.status.200:1|c",
                        metrics)
        assert.contains("prefix.service.statsdadvanced13.workspace." .. uuid_pattern .. ".status.200:1|c",
                        metrics, true)
        assert.contains("prefix.route." .. uuid_pattern .. ".user.robert.status.200:1|c", metrics, true)
        
        -- shdict_usage metrics, can't test again in 1 minutes
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
        assert.equal("kong.service.statsdadvanced5.request.count:1|c", res)
      end)
      it("status_count", function()
        local thread = helpers.udp_server(UDP_PORT)
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
        assert.matches("kong.service.statsdadvanced3.status.200:1|c", res)
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
        assert.matches("kong.service.statsdadvanced4.request.size:%d+|ms", res)
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
        assert.matches("kong.service.statsdadvanced2.latency:.*|ms", res)
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
        assert.matches("kong.service.statsdadvanced6.response.size:%d+|ms", res)
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
        assert.matches("kong.service.statsdadvanced7.upstream_latency:.*|ms", res)
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
        assert.matches("kong.service.statsdadvanced8.kong_latency:.*|ms", res)
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
        assert.matches("kong.service.statsdadvanced9.user.uniques:robert|s", res)
      end)
      it("status_count_per_user", function()
        local thread = helpers.udp_server(UDP_PORT)
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
        assert.matches("kong.service.statsdadvanced10.user.robert.status.200:1|c", res)
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
        assert.matches("kong.service.statsdadvanced11.user.bob.request.count:1|c", res)
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
        assert.matches("kong%.service.statsdadvanced12%.latency:%d+|g", res)
      end)
      it("consumer by consumer_id", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging14.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("^kong.service.statsdadvanced14.user.uniques:" .. uuid_pattern .. "|s", res)
      end)
    end)
  end)
end
