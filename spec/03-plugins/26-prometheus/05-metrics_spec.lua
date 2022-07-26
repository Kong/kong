local helpers = require "spec.helpers" -- hard dependency


local ngx = ngx

local fixtures = {
  dns_mock = helpers.dns_mock.new({
    mocks_only = true
  }),
  http_mock = {},
  stream_mock = {}
}

fixtures.dns_mock:A{
  name = "mock.example.com",
  address = "127.0.0.1"
}

fixtures.dns_mock:A{
  name = "status.example.com",
  address = "127.0.0.1"
}

local status_api_port = helpers.get_available_port()
local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: prometheus (metrics) [#" .. strategy .. "]", function()
    local bp
    local admin_ssl_client -- admin_ssl_client (lua-resty-http) does not support h2
    local proxy_ssl_client -- proxy_ssl_client (lua-resty-http) does not support h2

    setup(function()
      bp = helpers.get_db_utils(strategy, {"services", "routes", "plugins"})

      local mock_ssl_service = bp.services:insert{
        name = "mock-ssl-service",
        host = helpers.mock_upstream_ssl_host,
        port = helpers.mock_upstream_ssl_port,
        protocol = helpers.mock_upstream_ssl_protocol
      }
      bp.routes:insert{
        name = "mock-ssl-route",
        protocols = {"https"},
        hosts = {"mock.example.com"},
        paths = {"/"},
        service = {
            id = mock_ssl_service.id
        }
      }

      local status_api_ssl_service = bp.services:insert{
        name = "status-api-ssl-service",
        url = "https://127.0.0.1:" .. status_api_port .. "/metrics"
      }
      bp.routes:insert{
        name = "status-api-ssl-route",
        protocols = {"https"},
        hosts = {"status.example.com"},
        paths = {"/metrics"},
        service = {
          id = status_api_ssl_service.id
        }
      }

      bp.plugins:insert{
        name = "prometheus", -- globally enabled
        config = {
          status_code_metrics = true,
          latency_metrics = true,
          bandwidth_metrics = true,
          upstream_health_metrics = true,
        },
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,prometheus",
        status_listen = '127.0.0.1:' .. status_api_port .. ' ssl', -- status api does not support h2
        status_access_log = "logs/status_access.log",
        status_error_log = "logs/status_error.log"
      }, nil, nil, fixtures))

    end)

    teardown(function()
      if admin_ssl_client then
        admin_ssl_client:close()
      end
      if proxy_ssl_client then
        proxy_ssl_client:close()
      end

      helpers.stop_kong()
    end)

    before_each(function()
      admin_ssl_client = helpers.admin_client()
      proxy_ssl_client = helpers.proxy_ssl_client()
    end)

    after_each(function()
      if admin_ssl_client then
        admin_ssl_client:close()
      end
      if proxy_ssl_client then
        proxy_ssl_client:close()
      end
    end)

    it("expose Nginx connection metrics by admin API #a1.1", function()
      local res = assert(admin_ssl_client:send{
        method = "GET",
        path = "/metrics"
      })
      local body = assert.res_status(200, res)

      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
      assert.matches('kong_nginx_connections_total{node_id="' .. UUID_PATTERN .. '",subsystem="' .. ngx.config.subsystem .. '",state="%w+"} %d+', body)
    end)

    it("increments the count of proxied requests #p1.1", function()
      local res = assert(proxy_ssl_client:send{
        method = "GET",
        path = "/status/400",
        headers = {
          ["Host"] = "mock.example.com"
        }
      })
      assert.res_status(400, res)

      helpers.wait_until(function()
        local res = assert(admin_ssl_client:send{
          method = "GET",
          path = "/metrics"
        })
        local body = assert.res_status(200, res)

        assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

        return body:find('http_requests_total{service="mock-ssl-service",route="mock-ssl-route",code="400",source="service",consumer=""} 1',
          nil, true)
      end)
    end)

    it("expose Nginx connection metrics by status API #s1.1", function()
      local res = assert(proxy_ssl_client:send{
        method = "GET",
        path = "/metrics",
        headers = {
          ["Host"] = "status.example.com"
        }
      })
      local body = assert.res_status(200, res)

      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
      assert.matches('kong_nginx_connections_total{node_id="' .. UUID_PATTERN .. '",subsystem="' .. ngx.config.subsystem .. '",state="%w+"} %d+', body)
    end)

  end)
end
