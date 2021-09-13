local helpers = require "spec.helpers"

local tcp_status_port = helpers.get_available_port()

describe("Plugin: prometheus (Hybrid Mode)", function()
  local status_client

  setup(function()
    assert(helpers.start_kong {
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled",
      database = "off",
      role = "data_plane",
      cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
      status_listen = "0.0.0.0:" .. tcp_status_port,
    })
  end)


  before_each(function()
    status_client = helpers.http_client("127.0.0.1", tcp_status_port, 20000)
  end)

  after_each(function()
    if status_client then
      status_client:close()
    end
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("exposes data plane's cluster_cert expiry timestamp", function()
    local res = assert(status_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('data_plane_cluster_cert_expiry_timestamp %d+', body)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)
end)
