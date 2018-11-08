local helpers  = require "spec.helpers"
local cjson    = require "cjson"


local UDP_PORT = 20000

for _, strategy in helpers.each_strategy() do
  describe("Plugin-loop: log phase  [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      bp.routes:insert {
        hosts = { "udp_logging.com" },
      }

      bp.plugins:insert {
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
    end)

    teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("configures globally", function()
      it("sends log for non-matched route", function()

        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          headers = {
            host  = "logging1.com"
          }
        })
        assert.res_status(404, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        local log_message = cjson.decode(res)
        assert.equal("127.0.0.1", log_message.client_ip)
      end)
      it("sends log for matched route", function()

        local thread = helpers.udp_server(UDP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          headers = {
            host  = "udp_logging.com"
          }
        })
        assert.res_status(200, response)

        local ok, res = thread:join()
        assert.True(ok)
        assert.is_string(res)

        local log_message = cjson.decode(res)
        assert.equal("127.0.0.1", log_message.client_ip)
      end)
    end)
  end)
end
