local helpers = require "spec.helpers"

describe("Plugin: prometheus (custom server)",function()
  local proxy_client

  describe("with custom nginx server block", function()
    setup(function()
      local bp = helpers.get_db_utils()

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
        name = "prometheus"
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/prometheus/valid_nginx.template",
        plugins = "bundled, prometheus",
      }))

      proxy_client = helpers.proxy_client()
    end)
    teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    it("metrics can be read from a different port", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host = helpers.mock_upstream_host,
        }
      })
      assert.res_status(200, res)

      local client = helpers.http_client("127.0.0.1", 9542)
      res = assert(client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_http_status{code="200",service="mock-service"} 1', body, nil, true)
    end)
  end)
end)
