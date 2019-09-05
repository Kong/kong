local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: kafka-log (access)", function()
    local proxy_client
    local admin_client

    setup(function()
      local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        }, { "kafka-log" })

      local service = bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      }

      bp.routes:insert {
        protocols = { "http" },
        paths = { "/" },
        service = service,
      }

      bp.plugins:insert {
        name = "kafka-log",
        config = {
          bootstrap_servers = { "localhost:9092" },
          topic = "kong-log"
        }
      }

      assert(helpers.start_kong {
          nginx_conf = "spec/fixtures/1.2_custom_nginx.template",
          plugins = "bundled,kafka-log",
        })
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("at least, don't break proxied requests", function()
      local res = assert(proxy_client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            host = helpers.mock_upstream_host,
          }
        })
      assert.res_status(200, res)
    end)
  end)
end
