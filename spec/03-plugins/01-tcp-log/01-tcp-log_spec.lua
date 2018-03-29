local cjson    = require "cjson"
local helpers  = require "spec.helpers"


local TCP_PORT = 35001


for _, strategy in helpers.each_strategy() do
  describe("Plugin: tcp-log (log) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local route = bp.routes:insert {
        hosts = { "tcp_logging.com" },
      }

      bp.plugins:insert {
        route_id = route.id,
        name     = "tcp-log",
        config   = {
          host   = "127.0.0.1",
          port   = TCP_PORT,
        },
      }

      local route2 = bp.routes:insert {
        hosts = { "tcp_logging_tls.com" },
      }

      bp.plugins:insert {
        route_id = route2.id,
        name     = "tcp-log",
        config   = {
          host   = "127.0.0.1",
          port   = TCP_PORT,
          tls    = true,
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

    it("logs to TCP", function()
      local thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local r = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host  = "tcp_logging.com",
        },
      })
      assert.response(r).has.status(200)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.equal("127.0.0.1", log_message.client_ip)
    end)

    it("logs proper latencies", function()
      local tcp_thread = helpers.tcp_server(TCP_PORT) -- Starting the mock TCP server

      -- Making the request
      local r = assert(proxy_client:send {
        method  = "GET",
        path    = "/delay/2",
        headers = {
          host  = "tcp_logging.com",
        },
      })

      assert.response(r).has.status(200)
      -- Getting back the TCP server input
      local ok, res = tcp_thread:join()
      assert.True(ok)
      assert.is_string(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)

      assert.True(log_message.latencies.proxy < 3000)
      assert.True(log_message.latencies.request >= log_message.latencies.kong + log_message.latencies.proxy)
    end)

    it("performs a TLS handshake on the remote TCP server", function()
      local thread = helpers.tcp_server(TCP_PORT, { tls = true })

      -- Making the request
      local r = assert(proxy_client:send {
        method  = "GET",
        path    = "/request",
        headers = {
          host = "tcp_logging_tls.com",
        },
      })
      assert.response(r).has.status(200)

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
