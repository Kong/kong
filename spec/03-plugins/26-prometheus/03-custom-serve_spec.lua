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
        name = "http-route",
        paths = { "/" },
        service = service,
      }

      bp.plugins:insert {
        name = "prometheus",
        config = {
          status_code_metrics = true,
          latency_metrics = true,
          bandwidth_metrics = true,
          upstream_health_metrics = true,
        },
      }

      assert(helpers.start_kong({
        nginx_http_include = "../spec/fixtures/prometheus/metrics.conf",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
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
      assert.matches('http_requests_total{service="mock-service",route="http-route",code="200",source="service",consumer=""} 1', body, nil, true)
    end)
    it("custom port returns 404 for anything other than /metrics", function()
      local client = helpers.http_client("127.0.0.1", 9542)
      local res = assert(client:send {
        method  = "GET",
        path    = "/does-not-exists",
      })
      local body = assert.res_status(404, res)
      assert.matches('{"message":"Not found"}', body, nil, true)
    end)
  end)
end)
