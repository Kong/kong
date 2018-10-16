local helpers       = require "spec.helpers"
local vitals        = require "kong.vitals"
local pl_file       = require "pl.file"


local fmt = string.format


local UDP_PORT = 20000
local TCP_PORT = 20001

local stat_types = {
  gauge     = "g",
  counter   = "c",
  timer     = "ms",
  histogram = "h",
  meter     = "m",
  set       = "s",
}

local uuid_pattern = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"


-- All tests that test the extra metrics and feature of statsd-advanced compared to statsd CE go here


for _, strategy in helpers.each_strategy() do
  describe("Plugin: statsd-advanced (log) [#" .. strategy .. "]", function()
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

      local routes = {}
      for i = 1, 12 do
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

      for i = 100, 102 do
        local service = bp.services:insert {
          protocol = helpers.mock_upstream_protocol,
          host     = helpers.mock_upstream_host,
          port     = helpers.mock_upstream_port,
        }
        routes[i] = bp.routes:insert {
          hosts   = { fmt("logging%d.com", i) },
          service = service
        }
      end

      bp.key_auth_plugins:insert { route_id = routes[1].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[1].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
        },
      }

      bp.key_auth_plugins:insert { route_id = routes[2].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[2].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          prefix   = "prefix",
        },
      }

      bp.key_auth_plugins:insert { route_id = routes[3].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[3].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "status_count_per_user_per_route",
              stat_type           = "counter",
              consumer_identifier = "username",
              sample_rate         = 1,
            }
          },
        },
      }

      bp.key_auth_plugins:insert { route_id = routes[12].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[12].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                 = "status_count_per_workspace",
              stat_type            = "counter",
              sample_rate          = 1,
              workspace_identifier = "workspace_id",
            }
          },
        },
      }

      bp.key_auth_plugins:insert { route_id = routes[4].id }

      local vitals_metrics = {}
      for _, group in pairs(vitals.logging_metrics) do
        for metric, metric_type in pairs(group) do
          vitals_metrics[#vitals_metrics + 1] = {
            name        = metric,
            stat_type   = metric_type,
            sample_rate = 1
          }
        end
      end

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[4].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = vitals_metrics,
        },
      }


      bp.key_auth_plugins:insert { route_id = routes[5].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[5].id,
        config     = {
          host     = "127.0.0.1",
          port     = TCP_PORT,
          use_tcp  = true,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
            }
          },
        }
      }

      bp.key_auth_plugins:insert { route_id = routes[6].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[6].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
            },
            {
              name                = "upstream_latency",
              stat_type           = "timer",
            },
            {
              name                = "kong_latency",
              stat_type           = "timer",
            }
          },
          udp_packet_size = 500,
        }
      }

      bp.key_auth_plugins:insert { route_id = routes[7].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[7].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
            },
            {
              name                = "upstream_latency",
              stat_type           = "timer",
            },
            {
              name                = "kong_latency",
              stat_type           = "timer",
            }
          },
          udp_packet_size = 100,
        }
      }

      bp.key_auth_plugins:insert { route_id = routes[8].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[8].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
            },
            {
              name                = "upstream_latency",
              stat_type           = "timer",
            },
            {
              name                = "kong_latency",
              stat_type           = "timer",
            }
          },
          udp_packet_size = 1,
        }
      }

      bp.key_auth_plugins:insert { route_id = routes[9].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[9].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            -- test two types of metrics that are processed in different way
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_id",
            },
            {
              name                = "status_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_id",
            }
          },
        },
      }

      bp.key_auth_plugins:insert { route_id = routes[10].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[10].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_name",
            },
            {
              name                = "status_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_name",
            }
          },
        },
      }

      bp.key_auth_plugins:insert { route_id = routes[11].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[11].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_host",
            },
            {
              name                = "status_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_host",
            }
          },
        },
      }

      bp.key_auth_plugins:insert { route_id = routes[100].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[100].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_name_or_host",
            },
            {
              name                = "status_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_name_or_host",
            }
          },
        },
      }

      bp.key_auth_plugins:insert { route_id = routes[101].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[101].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_name",
            },
            {
              name                = "status_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_name",
            }
          },
        },
      }


      bp.key_auth_plugins:insert { route_id = routes[102].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[102].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                = "request_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_name",
            },
            {
              name                = "status_count",
              stat_type           = "counter",
              sample_rate         = 1,
              service_identifier  = "service_name",
            }
          },
          hostname_in_prefix = true,
        },
      }


      assert(helpers.start_kong({
        database   = strategy,
        -- this is to ensure we have the right number of shdicts being used so we know
        -- how many udp packets are we expecting below
        nginx_conf = "spec/fixtures/ee/custom_nginx_statsd_advanced.template", 
        custom_plugins = "statsd-advanced",
        vitals = "on"
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
      it("logs over UDP with default metrics with vitals on", function()
        local metrics_count = 12
        -- shdict_usage metrics
        metrics_count = metrics_count + (strategy == "cassandra" and 14 or 13) * 2
        -- vitals metrics
        for _, group in pairs(vitals.logging_metrics) do
          for metric, _ in pairs(group) do
            metrics_count = metrics_count + 1
          end
        end

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

        -- vitals metrics
        for _, group in pairs(vitals.logging_metrics) do
          for metric, metric_type in pairs(group) do
            assert.contains("kong.service.statsdadvanced1." .. metric .. ":%d+|" .. stat_types[metric_type],
                metrics, true)
          end
        end
      end)
      it("logs over UDP with default metrics and new prefix with vitals on", function()
        local metrics_count = 12
        -- shdict_usage metrics, can't test again in 1 minutes
        -- metrics_count = metrics_count + (strategy == "cassandra" and 14 or 13) * 2
        -- vitals metrics
        for _, group in pairs(vitals.logging_metrics) do
          for metric, _ in pairs(group) do
            metrics_count = metrics_count + 1
          end
        end

        local thread = helpers.udp_server(UDP_PORT, metrics_count)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging2.com"
          }
        })
        assert.res_status(200, response)

        local ok, metrics = thread:join()
        assert.True(ok)
        assert.contains("prefix.service.statsdadvanced2.request.count:1|c", metrics)
        assert.contains("prefix.service.statsdadvanced2.latency:%d+|ms", metrics, true)
        assert.contains("prefix.service.statsdadvanced2.request.size:110|ms", metrics)
        assert.contains("prefix.service.statsdadvanced2.status.200:1|c", metrics)
        assert.contains("prefix.service.statsdadvanced2.response.size:%d+|ms", metrics, true)
        assert.contains("prefix.service.statsdadvanced2.upstream_latency:%d*|ms", metrics, true)
        assert.contains("prefix.service.statsdadvanced2.kong_latency:%d*|ms", metrics, true)
        assert.contains("prefix.service.statsdadvanced2.user.uniques:robert|s", metrics)
        assert.contains("prefix.service.statsdadvanced2.user.robert.request.count:1|c", metrics)
        assert.contains("prefix.service.statsdadvanced2.user.robert.status.200:1|c",
                        metrics)
        assert.contains("prefix.service.statsdadvanced2.workspace." .. uuid_pattern .. ".status.200:1|c",
                        metrics, true)
        assert.contains("prefix.route." .. uuid_pattern .. ".user.robert.status.200:1|c", metrics, true)
        
        -- shdict_usage metrics, can't test again in 1 minutes

        -- vitals metrics
        for _, group in pairs(vitals.logging_metrics) do
          for metric, metric_type in pairs(group) do
            assert.contains("prefix.service.statsdadvanced2." .. metric .. ":%d+|" .. stat_types[metric_type],
                metrics, true)
          end
        end
      end)
      it("status_count_per_user_per_route", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging3.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.matches("kong.route." .. uuid_pattern .. ".user.bob.status.200:1|c", res)
      end)
      it("status_count_per_workspace", function()
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
        assert.matches("kong.service.statsdadvanced12.workspace." .. uuid_pattern .. ".status.200:1|c", res)
      end)
      it("vitals logging_metrics", function()
        local packet_count = 0
        for _, group in pairs(vitals.logging_metrics) do
          for metric, _ in pairs(group) do
            packet_count = packet_count + 1
          end
        end
        local thread = helpers.udp_server(UDP_PORT, packet_count)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging4.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)

        for _, group in pairs(vitals.logging_metrics) do
          for metric, metric_type in pairs(group) do
            assert.contains("kong.service.statsdadvanced4." .. metric .. ":[nil%d]+|" .. stat_types[metric_type],
            res, true)
          end
        end
      end)
      it("logs over TCP with one metric", function()
        local thread = helpers.tcp_server(TCP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging5.com"
          }
        })
        assert.res_status(200, response)

        local ok, metrics = thread:join()

        assert.True(ok)
        assert.matches("kong.service.statsdadvanced5.request.count:1|c", metrics)
      end)
      it("combines udp packets", function()
        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging6.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        -- doesn't has single of metrics packet
        assert.not_matches("^kong.service.statsdadvanced6.request.count:%d+|c$", res)
        assert.not_matches("^kong.service.statsdadvanced6.upstream_latency:%d+|ms$", res)
        assert.not_matches("^kong.service.statsdadvanced6.kong_latency:%d+|ms$", res)
        -- has a combined multi-metrics packet
        assert.matches("^kong.service.statsdadvanced6.request.count:%d+|c\n" ..
                        "kong.service.statsdadvanced6.upstream_latency:%d+|ms\n" ..
                        "kong.service.statsdadvanced6.kong_latency:%d+|ms$", res)
      end)
      it("combines and splits udp packets", function()
        local thread = helpers.udp_server(UDP_PORT, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging7.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        -- doesn't contain single of metrics packet
        assert.not_contains("^kong.service.statsdadvanced7.request.count:%d+|c$", res, true)
        assert.not_contains("^kong.service.statsdadvanced7.upstream_latency:%d+|ms$", res,  true)
        -- doesn't contain multi-metrics packet with all three metrics
        assert.not_contains("^kong.service.statsdadvanced7.request.count:%d+|c\n" ..
                        "kong.service.statsdadvanced7.upstream_latency:%d+|ms\n" ..
                        "kong.service.statsdadvanced7.kong_latency:%d+|ms$", res)
        -- has a combined multi-metrics packet with up to 100 bytes
        assert.contains("^kong.service.statsdadvanced7.request.count:%d+|c\n" ..
                        "kong.service.statsdadvanced7.upstream_latency:%d+|ms$", res, true)
        assert.contains("^kong.service.statsdadvanced7.kong_latency:%d+|ms$", res, true)
      end)
      it("throws an error if udp_packet_size is too small", function()
        local thread = helpers.udp_server(UDP_PORT, 3)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging8.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)

        assert.contains("^kong.service.statsdadvanced8.request.count:%d+|c$", res ,true)
        assert.contains("^kong.service.statsdadvanced8.upstream_latency:%d+|ms$", res, true)
        assert.contains("^kong.service.statsdadvanced8.kong_latency:%d+|ms$", res, true)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches("", err_log)
      end)
      it("logs service by service_id", function()
        local thread = helpers.udp_server(UDP_PORT, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging9.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.contains("^kong.service." .. uuid_pattern .. ".request.count:1|c$", res, true)
        assert.contains("^kong.service." .. uuid_pattern .. ".status.200:1|c$", res, true)
      end)
      it("logs service by service_host", function()
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
        assert.contains("^kong.service.statsdadvanced10.request.count:1|c$", res, true)
        assert.contains("^kong.service.statsdadvanced10.status.200:1|c$", res, true)
      end)
      it("logs service by service_name", function()
        local thread = helpers.udp_server(UDP_PORT, 2)
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
        assert.contains("^kong.service." .. string.gsub(helpers.mock_upstream_host, "%.", "_") .. 
                        ".request.count:1|c$", res, true)
        assert.contains("^kong.service." .. string.gsub(helpers.mock_upstream_host, "%.", "_") .. 
                        ".status.200:1|c$", res, true)
      end)
      it("logs service by service_name_or_host falls back to service host when service name is not set", function()
        local thread = helpers.udp_server(UDP_PORT, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging100.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.contains("^kong.service." .. string.gsub(helpers.mock_upstream_host, "%.", "_") ..
                       ".request.count:1|c$", res, true)
        assert.contains("^kong.service." .. string.gsub(helpers.mock_upstream_host, "%.", "_") ..
                       ".status.200:1|c$", res, true)
      end)
      it("logs service by service_name emits service.unnamed if service name is not set", function()
        local thread = helpers.udp_server(UDP_PORT, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging101.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.contains("^kong.service.unnamed.request.count:1|c$", res, true)
        assert.contains("^kong.service.unnamed.status.200:1|c$", res, true)
      end)
    end)

    describe("hostname_in_prefix", function()
      it("prefixes metric names with the hostname", function()
        local hostname = require("kong.tools.utils").get_hostname()
        hostname = string.gsub(hostname, "%.", "_")

        local thread = helpers.udp_server(UDP_PORT, metrics_count)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging102.com"
          }
        })
        assert.res_status(200, response)

        local ok, metrics = thread:join()
        assert.True(ok)
        assert.matches("kong.node." .. hostname .. ".service.unnamed.request.count:1|c", metrics, nil, true)
      end)
    end)
  end)

  describe("Plugin: statsd-advanced (log) [#" .. strategy .. "]", function()
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

      local routes = {}
      for i = 1, 1 do
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

      bp.key_auth_plugins:insert { route_id = routes[1].id }

      bp.plugins:insert {
        name     = "statsd-advanced",
        route_id   = routes[1].id,
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        -- this is to ensure we have deterministic number of shdicts that don't change over time
        -- how many udp packets are we expecting below
        nginx_conf = "spec/fixtures/ee/custom_nginx_statsd_advanced.template", 
        custom_plugins = "statsd-advanced",
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
      it("does not send vitals metrics when vitals is turned off", function()
        local metrics_count = 12
        -- shdict_usage metrics
        metrics_count = metrics_count + (strategy == "cassandra" and 14 or 13) * 2
        -- should have no vitals metrics

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

        -- vitals metrics should not be send, should not send metrics with value nil
        for _, group in pairs(vitals.logging_metrics) do
          for metric, metric_type in pairs(group) do
            assert.not_contains("kong.service.statsdadvanced1." .. metric .. ":[nil%d]+|" .. stat_types[metric_type],
                metrics, true)
          end
        end
      end)
    end)
  end)
  
  describe("Plugin: statsd-advanced (log) [#" .. strategy .. "]", function()
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

      bp.plugins:insert { name = "key-auth" }

      bp.plugins:insert {
        name     = "statsd-advanced",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        -- this is to ensure we have the right number of shdicts being used so we know
        -- how many udp packets are we expecting below
        nginx_conf = "spec/fixtures/ee/custom_nginx_statsd_advanced.template", 
        custom_plugins = "statsd-advanced",
      }))

      proxy_client = helpers.proxy_client()
    end)

    teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("configures globally", function()
      it("sends default metrics with global.matched namespace", function()
        local metrics_count = 6 -- 6 less than normal
        -- should have no shdict_usage metrics
        -- metrics_count = metrics_count + (strategy == "cassandra" and 14 or 13) * 2
        -- should have no vitals metrics

        local thread = helpers.udp_server(UDP_PORT, metrics_count)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging1.com"
          }
        })
        assert.res_status(404, response)

        local ok, metrics = thread:join()
        assert.True(ok)
        assert.contains("kong.global.unmatched.request.count:1|c", metrics)
        assert.contains("kong.global.unmatched.latency:%d+|ms", metrics, true)
        assert.contains("kong.global.unmatched.request.size:%d+|ms", metrics, true)
        assert.contains("kong.global.unmatched.status.404:1|c", metrics)
        assert.contains("kong.global.unmatched.response.size:%d+|ms", metrics, true)
        assert.not_contains("kong.global.unmatched.upstream_latency:%d*|ms", metrics, true)
        assert.contains("kong.global.unmatched.kong_latency:%d+|ms", metrics, true)
        assert.not_contains("kong.global.unmatched.user.uniques:robert|s", metrics)
        assert.not_contains("kong.global.unmatched.user.robert.request.count:1|c", metrics)
        assert.not_contains("kong.global.unmatched.user.robert.status.404:1|c",
                        metrics)
        assert.not_contains("kong.global.unmatched.workspace." .. uuid_pattern .. ".status.200:1|c",
                        metrics, true)
        assert.not_contains("kong.route." .. uuid_pattern .. ".user.robert.status.404:1|c", metrics, true)
        
        -- shdict_usage metrics, just test one is enough
        assert.not_contains("kong.node..*.shdict.kong.capacity:%d+|g", metrics, true)
        assert.not_contains("kong.node..*.shdict.kong.free_space:%d+|g", metrics, true)

        -- vitals metrics should not be send, should not send metrics with value nil
        for _, group in pairs(vitals.logging_metrics) do
          for metric, metric_type in pairs(group) do
            assert.not_contains("kong.global.unmatched." .. metric .. ":[nil%d]+|" .. stat_types[metric_type],
                metrics, true)
          end
        end
      end)
    end)
  end)
end
