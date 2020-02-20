local helpers = require "spec.helpers"
local pl_file = require "pl.file"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: datadog (log) [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local consumer = bp.consumers:insert {
        username  = "foo",
        custom_id = "bar"
      }

      bp.keyauth_credentials:insert({
        key      = "kong",
        consumer = { id = consumer.id },
      })

      local route1 = bp.routes:insert {
        hosts   = { "datadog1.com" },
        service = bp.services:insert { name = "dd1" }
      }

      local route2 = bp.routes:insert {
        hosts   = { "datadog2.com" },
        service = bp.services:insert { name = "dd2" }
      }

      local route3 = bp.routes:insert {
        hosts   = { "datadog3.com" },
        service = bp.services:insert { name = "dd3" }
      }

      local route4 = bp.routes:insert {
        hosts   = { "datadog4.com" },
        service = bp.services:insert { name = "dd4" }
      }

      bp.plugins:insert {
        name     = "key-auth",
        route = { id = route1.id },
      }

      bp.plugins:insert {
        name     = "datadog",
        route = { id = route1.id },
        config   = {
          host   = "127.0.0.1",
          port   = 9999,
        },
      }

      bp.plugins:insert {
        name     = "datadog",
        route = { id = route2.id },
        config   = {
          host    = "127.0.0.1",
          port    = 9999,
          metrics = {
            {
              name        = "request_count",
              stat_type   = "counter",
              sample_rate = 1,
            },
          },
        },
      }

      bp.plugins:insert {
        name     = "datadog",
        route = { id = route3.id },
        config   = {
          host    = "127.0.0.1",
          port    = 9999,
          metrics = {
            {
              name        = "request_count",
              stat_type   = "counter",
              sample_rate = 1,
              tags        = {"T2:V2", "T3:V3", "T4"},
            },
            {
              name        = "latency",
              stat_type   = "gauge",
              sample_rate = 1,
              tags        = {"T2:V2:V3", "T4"},
            },
          },
        },
      }

      bp.plugins:insert {
        name       = "key-auth",
        route = { id = route4.id },
      }

      bp.plugins:insert {
        name     = "datadog",
        route = { id = route4.id },
        config   = {
          host   = "127.0.0.1",
          port   = 9999,
          prefix = "prefix",
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)
    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("logs metrics over UDP", function()
      local thread = helpers.udp_server(9999, 6)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=kong",
        headers = {
          ["Host"] = "datadog1.com"
        }
      })
      assert.res_status(200, res)

      local ok, gauges = thread:join()
      assert.True(ok)
      assert.equal(6, #gauges)
      assert.contains("kong.request.count:1|c|#name:dd1,status:200,consumer:bar,app:kong" , gauges)
      assert.contains("kong.latency:%d+|ms|#name:dd1,status:200,consumer:bar,app:kong", gauges, true)
      assert.contains("kong.request.size:%d+|ms|#name:dd1,status:200,consumer:bar,app:kong", gauges, true)
      assert.contains("kong.response.size:%d+|ms|#name:dd1,status:200,consumer:bar,app:kong", gauges, true)
      assert.contains("kong.upstream_latency:%d+|ms|#name:dd1,status:200,consumer:bar,app:kong", gauges, true)
      assert.contains("kong.kong_latency:%d*|ms|#name:dd1,status:200,consumer:bar,app:kong", gauges, true)
    end)

    it("logs metrics over UDP with custom prefix", function()
      local thread = helpers.udp_server(9999, 6)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200?apikey=kong",
        headers = {
          ["Host"] = "datadog4.com"
        }
      })
      assert.res_status(200, res)

      local ok, gauges = thread:join()
      assert.True(ok)
      assert.equal(6, #gauges)
      assert.contains("prefix.request.count:1|c|#name:dd4,status:200,consumer:bar,app:kong",gauges)
      assert.contains("prefix.latency:%d+|ms|#name:dd4,status:200,consumer:bar,app:kong", gauges, true)
      assert.contains("prefix.request.size:%d+|ms|#name:dd4,status:200,consumer:bar,app:kong", gauges, true)
      assert.contains("prefix.response.size:%d+|ms|#name:dd4,status:200,consumer:bar,app:kong", gauges, true)
      assert.contains("prefix.upstream_latency:%d+|ms|#name:dd4,status:200,consumer:bar,app:kong", gauges, true)
      assert.contains("prefix.kong_latency:%d*|ms|#name:dd4,status:200,consumer:bar,app:kong", gauges, true)
    end)

    it("logs only given metrics", function()
      local thread = helpers.udp_server(9999, 1)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          ["Host"] = "datadog2.com"
        }
      })
      assert.res_status(200, res)

      local ok, gauges = thread:join()
      assert.True(ok)
      gauges = { gauges } -- as thread:join() returns a string in case of 1
      assert.equal(1, #gauges)
      assert.contains("kong.request.count:1|c|#name:dd2,status:200", gauges)
    end)

    it("logs metrics with tags", function()
      local thread = helpers.udp_server(9999, 2)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          ["Host"] = "datadog3.com"
        }
      })
      assert.res_status(200, res)

      local ok, gauges = thread:join()
      assert.True(ok)
      assert.contains("kong.request.count:1|c|#name:dd3,status:200,T2:V2,T3:V3,T4", gauges)
      assert.contains("kong.latency:%d+|g|#name:dd3,status:200,T2:V2:V3,T4", gauges, true)
    end)

    it("should not return a runtime error (regression)", function()
      local thread = helpers.udp_server(9999, 1, 1)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/NonMatch",
        headers = {
          ["Host"] = "fakedns.com"
        }
      })

      assert.res_status(404, res)

      local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
      assert.not_matches("attempt to index field 'api' (a nil value)", err_log, nil, true)

      -- make a valid request to make thread end
      assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          ["Host"] = "datadog3.com"
        }
      })

      thread:join()
    end)
  end)
end
