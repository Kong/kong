local cjson    = require "cjson"
local helpers  = require "spec.helpers"


local UDP_PORT = 35001


for _, strategy in helpers.each_strategy() do
  describe("Plugin: udp-log (log) [#" .. strategy .. "]", function()
    local proxy_client
    local proxy_client_grpc, proxy_client_grpcs

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route = bp.routes:insert {
        hosts = { "udp_logging.com" },
      }

      bp.plugins:insert {
        route = { id = route.id },
        name     = "udp-log",
        config   = {
          host   = "127.0.0.1",
          port   = UDP_PORT
        },
      }

      local grpc_service = assert(bp.services:insert {
        name = "grpc-service",
        url = "grpc://localhost:15002",
      })

      local route2 = assert(bp.routes:insert {
        service = grpc_service,
        protocols = { "grpc" },
        hosts = { "udp_logging_grpc.test" },
      })

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "udp-log",
        config   = {
          host   = "127.0.0.1",
          port   = UDP_PORT
        },
      }

      local grpcs_service = assert(bp.services:insert {
        name = "grpcs-service",
        url = "grpcs://localhost:15003",
      })

      local route3 = assert(bp.routes:insert {
        service = grpcs_service,
        protocols = { "grpcs" },
        hosts = { "udp_logging_grpcs.test" },
      })

      bp.plugins:insert {
        route = { id = route3.id },
        name     = "udp-log",
        config   = {
          host   = "127.0.0.1",
          port   = UDP_PORT
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      proxy_client_grpc = helpers.proxy_client_grpc()
      proxy_client_grpcs = helpers.proxy_client_grpcs()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("logs proper latencies", function()
      local udp_thread = helpers.udp_server(UDP_PORT)

      -- Making the request
      local r = assert(proxy_client:send {
        method  = "GET",
        path    = "/delay/2",
        headers = {
          host  = "udp_logging.com",
        },
      })

      assert.response(r).has.status(200)
      -- Getting back the UDP server input
      local ok, res = udp_thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.True(log_message.latencies.proxy < 3000)

      -- Sometimes there's a split milisecond that makes numbers not
      -- add up by 1. Adding an artificial 1 to make the test
      -- resilient to those.
      local is_latencies_sum_adding_up =
        1+log_message.latencies.request >= log_message.latencies.kong +
        log_message.latencies.proxy

      assert.True(is_latencies_sum_adding_up)
    end)

    it("logs proper latencies (#grpc) #flaky", function()
      local udp_thread = helpers.udp_server(UDP_PORT)

      -- Making the request
      local ok, resp = proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "udp_logging_grpc.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the UDP server input
      local ok, res = udp_thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.True(log_message.latencies.proxy < 3000)

      -- Sometimes there's a split milisecond that makes numbers not
      -- add up by 1. Adding an artificial 1 to make the test
      -- resilient to those.
      local is_latencies_sum_adding_up =
        1+log_message.latencies.request >= log_message.latencies.kong +
        log_message.latencies.proxy

      assert.True(is_latencies_sum_adding_up)
    end)

    it("logs proper latencies (#grpcs) #flaky", function()
      local udp_thread = helpers.udp_server(UDP_PORT)

      -- Making the request
      local ok, resp = proxy_client_grpcs({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "udp_logging_grpcs.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the UDP server input
      local ok, res = udp_thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.True(log_message.latencies.proxy < 3000)

      -- Sometimes there's a split milisecond that makes numbers not
      -- add up by 1. Adding an artificial 1 to make the test
      -- resilient to those.
      local is_latencies_sum_adding_up =
        1+log_message.latencies.request >= log_message.latencies.kong +
        log_message.latencies.proxy

      assert.True(is_latencies_sum_adding_up)
    end)

    it("logs to UDP", function()
      local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

      -- Making the request
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host  = "udp_logging.com",
        },
      })
      assert.response(res).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)
    end)

    it("logs to UDP (#grpc)", function()
      local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

      -- Making the request
      local ok, resp = proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "udp_logging_grpc.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)
    end)

    it("logs to UDP (#grpcs)", function()
      local thread = helpers.udp_server(UDP_PORT) -- Starting the mock UDP server

      -- Making the request
      local ok, resp = proxy_client_grpcs({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-authority"] = "udp_logging_grpcs.test",
        }
      })
      assert.truthy(ok)
      assert.truthy(resp)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)
    end)
  end)
end
