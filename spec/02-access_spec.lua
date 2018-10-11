local helpers = require "spec.helpers"

describe("Plugin: prometheus (access)", function()
  local proxy_client
  local admin_client

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

    assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled, prometheus",
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

  it("increments the count for proxied requests", function()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/200",
      headers = {
        host = helpers.mock_upstream_host,
      }
    })
    assert.res_status(200, res)
    res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_http_status{code="200",service="mock-service"} 1', body, nil, true)

    ngx.sleep(1)
    res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/400",
      headers = {
        host = helpers.mock_upstream_host,
      }
    })
    assert.res_status(400, res)

    res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    body = assert.res_status(200, res)
    assert.matches('kong_http_status{code="400",service="mock-service"} 1', body, nil, true)
  end)
end)
