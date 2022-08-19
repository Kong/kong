local helpers       = require "spec.helpers"
local pl_file       = require "pl.file"

local get_hostname = require("kong.pdk.node").new().get_hostname


local fmt = string.format


local UDP_PORT = 20000
local TCP_PORT = 20001


local uuid_pattern = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
local workspace_name_pattern = "default"


local function get_shdicts()
  local prefix = helpers.test_conf.prefix
  local ngxconf = helpers.utils.readfile(prefix .. "/nginx.conf")
  local pattern = "\n%s*lua_shared_dict%s+(.-)[%s;\n]"
  local shdicts = {}
  for dict_name in ngxconf:gmatch(pattern) do
    table.insert(shdicts, dict_name)
    --print(#shdicts, "-", dict_name)
  end
  return shdicts
end


for _, strategy in helpers.each_strategy() do
  describe("Plugin: statsd (log) [#" .. strategy .. "]", function()
    local proxy_client
    local proxy_client_grpc
    local shdict_count

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
      for i = 1, 30 do
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

      bp.key_auth_plugins:insert { route = { id = routes[14].id } }

      bp.statsd_plugins:insert {
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

      bp.key_auth_plugins:insert { route = { id = routes[15].id } }
      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[15].id },
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

      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[16].id },
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

      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[17].id },
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
          metrics  = {
            {
              name                 = "status_count_per_workspace",
              stat_type            = "counter",
              sample_rate          = 1,
              workspace_identifier = "workspace_name",
            }
          },
        },
      }

      bp.key_auth_plugins:insert { route = { id = routes[18].id } }
      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[18].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[19].id } }
      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[19].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[20].id } }
      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[20].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[21].id } }
      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[21].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[22].id } }
      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[22].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[23].id } }
      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[23].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[24].id } }
      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[24].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[100].id } }

      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[100].id },
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

      bp.key_auth_plugins:insert { route = { id = routes[101].id } }

      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[101].id },
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


      bp.key_auth_plugins:insert { route = { id = routes[102].id } }

      bp.plugins:insert {
        name     = "statsd",
        route      = { id = routes[102].id },
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

      -- grpc
      local grpc_routes = {}
      for i = 1, 2 do
        local service = bp.services:insert {
          url = helpers.grpcbin_url,
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
      shdict_count = #get_shdicts()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("metrics", function()
      it("logs over UDP with default metrics", function()
        local metrics_count = 12
        -- shdict_usage metrics
        metrics_count = metrics_count + shdict_count * 2

        local thread = helpers.udp_server(UDP_PORT, metrics_count, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging1.com"
          }
        })
        assert.res_status(200, response)

        local ok, metrics, err = thread:join()
        assert(ok, metrics)
        assert(#metrics == metrics_count, err)
        assert.contains("kong.service.statsd1.request.count:1|c", metrics)
        assert.contains("kong.service.statsd1.request.size:%d+|ms", metrics, true)
        assert.contains("kong.service.statsd1.response.size:%d+|ms", metrics, true)
        assert.contains("kong.service.statsd1.latency:%d+|ms", metrics, true)
        assert.contains("kong.service.statsd1.status.200:1|c", metrics)
        assert.contains("kong.service.statsd1.upstream_latency:%d*|ms", metrics, true)
        assert.contains("kong.service.statsd1.kong_latency:%d*|ms", metrics, true)
        assert.contains("kong.service.statsd1.user.uniques:robert|s", metrics)
        assert.contains("kong.service.statsd1.user.robert.request.count:1|c", metrics)
        assert.contains("kong.service.statsd1.user.robert.status.200:1|c", metrics)

        assert.contains("kong.service.statsd1.workspace." .. uuid_pattern .. ".status.200:1|c", metrics, true)
        assert.contains("kong.route." .. uuid_pattern .. ".user.robert.status.200:1|c", metrics, true)

        -- shdict_usage metrics, just test one is enough
        assert.contains("kong.node..*.shdict.kong.capacity:%d+|g", metrics, true)
        assert.contains("kong.node..*.shdict.kong.free_space:%d+|g", metrics, true)
      end)
      it("logs over UDP with default metrics and new prefix", function()
        local metrics_count = 12
        -- shdict_usage metrics, can't test again in 1 minutes
        -- metrics_count = metrics_count + shdict_count * 2


        local thread = helpers.udp_server(UDP_PORT, metrics_count, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging13.com"
          }
        })
        assert.res_status(200, response)
        local ok, metrics, err = thread:join()
        assert(ok, metrics)
        assert(#metrics == metrics_count, err)
        assert.contains("prefix.service.statsd13.request.count:1|c", metrics)
        assert.contains("prefix.service.statsd13.latency:%d+|ms", metrics, true)
        assert.contains("prefix.service.statsd13.request.size:%d+|ms", metrics, true)
        assert.contains("prefix.service.statsd13.status.200:1|c", metrics)
        assert.contains("prefix.service.statsd13.response.size:%d+|ms", metrics, true)
        assert.contains("prefix.service.statsd13.upstream_latency:%d*|ms", metrics, true)
        assert.contains("prefix.service.statsd13.kong_latency:%d*|ms", metrics, true)
        assert.contains("prefix.service.statsd13.user.uniques:robert|s", metrics)
        assert.contains("prefix.service.statsd13.user.robert.request.count:1|c", metrics)
        assert.contains("prefix.service.statsd13.user.robert.status.200:1|c", metrics)

        assert.contains("prefix.service.statsd13.workspace." .. uuid_pattern .. ".status.200:1|c",
          metrics, true)
        assert.contains("prefix.route." .. uuid_pattern .. ".user.robert.status.200:1|c", metrics, true)
      end)
      it("request_count", function()
        local thread = helpers.udp_server(UDP_PORT, 1, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            host  = "logging5.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(res, err)
        assert.equal("kong.service.statsd5.request.count:1|c", res)
      end)
      it("status_count", function()
        local thread = helpers.udp_server(UDP_PORT, 2,2)
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
        assert.contains("kong.service.statsd3.status.200:1|c", res)
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
        assert.matches("kong.service.statsd4.request.size:%d+|ms", res)
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
        assert.matches("kong.service.statsd2.latency:.*|ms", res)
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
        assert.matches("kong.service.statsd6.response.size:%d+|ms", res)
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
        assert.matches("kong.service.statsd7.upstream_latency:.*|ms", res)
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
        assert.matches("kong.service.statsd8.kong_latency:.*|ms", res)
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
        assert.matches("kong.service.statsd9.user.uniques:robert|s", res)
      end)
      it("status_count_per_user", function()
        local thread = helpers.udp_server(UDP_PORT, 2, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging10.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(res, err)
        assert.contains("kong.service.statsd10.user.robert.status.200:1|c", res)
      end)
      it("request_per_user", function()
        local thread = helpers.udp_server(UDP_PORT, 1, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging11.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(res, err)
        assert.matches("kong.service.statsd11.user.bob.request.count:1|c", res)
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
        assert.matches("kong%.service.statsd12.latency:%d+|g", res)
      end)
      it("consumer by consumer_id", function()
        local thread = helpers.udp_server(UDP_PORT, 1, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging14.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(res, err)
        assert.matches("^kong.service.statsd14.user.uniques:" .. uuid_pattern .. "|s", res)
      end)
      it("status_count_per_user_per_route", function()
        local thread = helpers.udp_server(UDP_PORT, 1, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging15.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(res, err)
        assert.matches("kong.route." .. uuid_pattern .. ".user.bob.status.200:1|c", res)
      end)
      it("status_count_per_workspace", function()
        local thread = helpers.udp_server(UDP_PORT, 1, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging16.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(res, err)
        assert.matches("kong.service.statsd16.workspace." .. uuid_pattern .. ".status.200:1|c", res)
      end)
      it("status_count_per_workspace", function()
        local thread = helpers.udp_server(UDP_PORT, 1, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging17.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(res, err)
        assert.matches("kong.service.statsd17.workspace." .. workspace_name_pattern .. ".status.200:1|c", res)
      end)
      it("logs over TCP with one metric", function()
        local thread = helpers.tcp_server(TCP_PORT, { timeout = 10 })
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging18.com"
          }
        })
        assert.res_status(200, response)

        local ok, metrics = thread:join()

        assert.True(ok)
        assert.matches("kong.service.statsd18.request.count:1|c", metrics)
      end)
      it("combines udp packets", function()
        local thread = helpers.udp_server(UDP_PORT, 1, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging19.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(res, err)
        -- doesn't has single of metrics packet
        assert.not_matches("^kong.service.statsd19.request.count:%d+|c$", res)
        assert.not_matches("^kong.service.statsd19.upstream_latency:%d+|ms$", res)
        assert.not_matches("^kong.service.statsd19.kong_latency:%d+|ms$", res)
        -- has a combined multi-metrics packet
        assert.matches("^kong.service.statsd19.request.count:%d+|c\n" ..
          "kong.service.statsd19.upstream_latency:%d+|ms\n" ..
          "kong.service.statsd19.kong_latency:%d+|ms$", res)
      end)
      it("combines and splits udp packets", function()
        local thread = helpers.udp_server(UDP_PORT, 2, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging20.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(#res == 2, err)
        -- doesn't contain single of metrics packet
        assert.not_contains("^kong.service.statsd20.request.count:%d+|c$", res, true)
        assert.not_contains("^kong.service.statsd20.upstream_latency:%d+|ms$", res,  true)
        -- doesn't contain multi-metrics packet with all three metrics
        assert.not_contains("^kong.service.stats20.request.count:%d+|c\n" ..
          "kong.service.statsd20.upstream_latency:%d+|ms\n" ..
          "kong.service.statsd20.kong_latency:%d+|ms$", res)
        -- has a combined multi-metrics packet with up to 100 bytes
        assert.contains("^kong.service.statsd20.request.count:%d+|c\n" .. "kong.service.statsd20.upstream_latency:%d+|ms$", res, true)
        assert.contains("^kong.service.statsd20.kong_latency:%d+|ms$", res, true)
      end)
      it("throws an error if udp_packet_size is too small", function()
        local thread = helpers.udp_server(UDP_PORT, 3, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging21.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(#res == 3, err)

        assert.contains("^kong.service.statsd21.request.count:%d+|c$", res ,true)
        assert.contains("^kong.service.statsd21.upstream_latency:%d+|ms$", res, true)
        assert.contains("^kong.service.statsd21.kong_latency:%d+|ms$", res, true)

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches("", err_log)
      end)
      it("logs service by service_id", function()
        local thread = helpers.udp_server(UDP_PORT, 2, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging22.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(#res == 2, err)
        assert.contains("^kong.service." .. uuid_pattern .. ".request.count:1|c$", res, true)
        assert.contains("^kong.service." .. uuid_pattern .. ".status.200:1|c$", res, true)
      end)
      it("logs service by service_host", function()
        local thread = helpers.udp_server(UDP_PORT, 2, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging23.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(#res == 2, err)
        assert.contains("^kong.service.statsd23.request.count:1|c$", res, true)
        assert.contains("^kong.service.statsd23.status.200:1|c$", res, true)
      end)
      it("logs service by service_name", function()
        local thread = helpers.udp_server(UDP_PORT, 2, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging24.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(#res == 2, err)
        assert.contains("^kong.service." .. string.gsub(helpers.mock_upstream_host, "%.", "_") ..
          ".request.count:1|c$", res, true)
        assert.contains("^kong.service." .. string.gsub(helpers.mock_upstream_host, "%.", "_") ..
          ".status.200:1|c$", res, true)
      end)
      it("logs service by service_name_or_host falls back to service host when service name is not set", function()
        local thread = helpers.udp_server(UDP_PORT, 2, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging100.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(#res == 2, err)
        assert.contains("^kong.service." .. string.gsub(helpers.mock_upstream_host, "%.", "_") ..
          ".request.count:1|c$", res, true)
        assert.contains("^kong.service." .. string.gsub(helpers.mock_upstream_host, "%.", "_") ..
          ".status.200:1|c$", res, true)
      end)
      it("logs service by service_name emits unnamed if service name is not set", function()
        local thread = helpers.udp_server(UDP_PORT, 2, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging101.com"
          }
        })
        assert.res_status(200, response)

        local ok, res, err = thread:join()
        assert(ok, res)
        assert(#res == 2, err)
        assert.contains("^kong.service.unnamed.request.count:1|c$", res, true)
        assert.contains("^kong.service.unnamed.status.200:1|c$", res, true)
      end)
    end)

    describe("hostname_in_prefix", function()
      it("prefixes metric names with the hostname", function()
        local hostname = get_hostname()
        hostname = string.gsub(hostname, "%.", "_")

        local thread = helpers.udp_server(UDP_PORT, 1, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging102.com"
          }
        })
        assert.res_status(200, response)

        local ok, metrics, err = thread:join()
        assert(ok, metrics)
        assert(metrics, err)
        assert.matches("kong.node." .. hostname .. ".service.unnamed.request.count:1|c", metrics, nil, true)
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
        assert.contains("kong.service.grpc_statsd1.request.count:1|c", metrics)
        assert.contains("kong.service.grpc_statsd1.latency:%d+|ms", metrics, true)
        assert.contains("kong.service.grpc_statsd1.request.size:%d+|ms", metrics, true)
        assert.contains("kong.service.grpc_statsd1.status.200:1|c", metrics)
        assert.contains("kong.service.grpc_statsd1.response.size:%d+|ms", metrics, true)
        assert.contains("kong.service.grpc_statsd1.upstream_latency:%d*|ms", metrics, true)
        assert.contains("kong.service.grpc_statsd1.kong_latency:%d*|ms", metrics, true)
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
        assert.matches("kong%.service%.grpc_statsd2%.latency:%d+|g", res)
      end)
    end)
  end)

  describe("Plugin: statsd (log) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local consumer = bp.consumers:insert {
        username  = "bob",
        custom_id = "robert",
      }

      bp.keyauth_credentials:insert {
        key         = "kong",
        consumer    = { id = consumer.id },
      }

      bp.plugins:insert { name = "key-auth" }

      bp.plugins:insert {
        name     = "statsd",
        config     = {
          host     = "127.0.0.1",
          port     = UDP_PORT,
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

    describe("configures globally", function()
      it("sends default metrics with global.matched namespace", function()
        local metrics_count = 6
        -- should have no shdict_usage metrics
        -- metrics_count = metrics_count + shdict_count * 2
        -- should have no vitals metrics

        local thread = helpers.udp_server(UDP_PORT, metrics_count, 2)
        local response = assert(proxy_client:send {
          method  = "GET",
          path    = "/request?apikey=kong",
          headers = {
            host  = "logging1.com"
          }
        })
        assert.res_status(404, response)

        local ok, metrics, err = thread:join()
        assert(ok, metrics)
        assert(#metrics == metrics_count, err)
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
      end)
    end)
  end)
end
