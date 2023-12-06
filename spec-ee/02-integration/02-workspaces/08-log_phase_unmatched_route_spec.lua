-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers  = require "spec.helpers"
local cjson    = require "cjson"


local TCP_PORT = 20000

for _, strategy in helpers.each_strategy() do
  describe("Plugin-loop: log phase  [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      bp.routes:insert {
        hosts = { "tcp_logging.test" },
      }

      bp.plugins:insert {
        name     = "tcp-log",
        config   = {
          host   = "127.0.0.1",
          port   = TCP_PORT
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

        local thread = helpers.tcp_server(TCP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          headers = {
            host  = "logging1.test"
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

        local thread = helpers.tcp_server(TCP_PORT)
        local response = assert(proxy_client:send {
          method  = "GET",
          headers = {
            host  = "tcp_logging.test"
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
