local helpers = require "spec.helpers"

local tcp_service_port = helpers.get_available_port()
local tcp_proxy_port = helpers.get_available_port()

describe("Plugin: prometheus (access)", function()
  local proxy_client
  local admin_client
  local proxy_client_grpc
  local proxy_client_grpcs

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
      methods = { "GET" },
      service = service,
    }

    local grpc_service = bp.services:insert {
      name = "mock-grpc-service",
      url = "grpc://localhost:15002",
    }

    bp.routes:insert {
      protocols = { "grpc" },
      name = "grpc-route",
      hosts = { "grpc" },
      service = grpc_service,
    }

    local grpcs_service = bp.services:insert {
      name = "mock-grpcs-service",
      url = "grpcs://localhost:15003",
    }

    bp.routes:insert {
      protocols = { "grpcs" },
      name = "grpcs-route",
      hosts = { "grpcs" },
      service = grpcs_service,
    }

    local tcp_service = bp.services:insert {
      name = "tcp-service",
      url = "tcp://127.0.0.1:" .. tcp_service_port,
    }

    bp.routes:insert {
      protocols = { "tcp" },
      name = "tcp-route",
      service = tcp_service,
      destinations = { { port = tcp_proxy_port } },
    }

    bp.plugins:insert {
      protocols = { "http", "https", "grpc", "grpcs", "tcp", "tls" },
      name = "prometheus"
    }

    assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
        stream_listen = "127.0.0.1:" .. tcp_proxy_port,
    })
    proxy_client = helpers.proxy_client()
    admin_client = helpers.admin_client()
    proxy_client_grpc = helpers.proxy_client_grpc()
    proxy_client_grpcs = helpers.proxy_client_grpcs()
  end)

  teardown(function()
    if proxy_client then
      proxy_client:close()
    end
    if admin_client then
      admin_client:close()
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

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

      return body:find('kong_http_status{service="mock-service",route="http-route",code="200"} 1', nil, true)
    end)

    res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/400",
      headers = {
        host = helpers.mock_upstream_host,
      }
    })
    assert.res_status(400, res)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

      return body:find('kong_http_status{service="mock-service",route="http-route",code="400"} 1', nil, true)
    end)
  end)

  it("increments the count for proxied grpc requests", function()
    local ok, resp = proxy_client_grpc({
      service = "hello.HelloService.SayHello",
      body = {
        greeting = "world!"
      },
      opts = {
        ["-authority"] = "grpc",
      }
    })
    assert(ok, resp)
    assert.truthy(resp)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

      return body:find('kong_http_status{service="mock-grpc-service",route="grpc-route",code="200"} 1', nil, true)
    end)

    ok, resp = proxy_client_grpcs({
      service = "hello.HelloService.SayHello",
      body = {
        greeting = "world!"
      },
      opts = {
        ["-authority"] = "grpcs",
      }
    })
    assert(ok, resp)
    assert.truthy(resp)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

      return body:find('kong_http_status{service="mock-grpcs-service",route="grpcs-route",code="200"} 1', nil, true)
    end)
  end)

  it("increments the count for proxied TCP streams", function()
    local thread = helpers.tcp_server(tcp_service_port, { requests = 1 })

    local conn = assert(ngx.socket.connect("127.0.0.1", tcp_proxy_port))

    assert(conn:send("hi there!\n"))
    local gotback = assert(conn:receive("*a"))
    assert.equal("hi there!\n", gotback)

    conn:close()

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

      return body:find('kong_stream_status{service="tcp-service",route="tcp-route",code="200"} 1', nil, true)
    end)

    thread:join()
  end)

  it("does not log error if no service was matched", function()
    -- cleanup logs
    os.execute(":> " .. helpers.test_conf.nginx_err_logs)

    local res = assert(proxy_client:send {
      method  = "POST",
      path    = "/no-route-match-in-kong",
    })
    assert.res_status(404, res)

    -- make sure no errors
    assert.logfile().has.no.line("[error]", true, 10)
  end)

  it("does not log error during a scrape", function()
    -- cleanup logs
    os.execute(":> " .. helpers.test_conf.nginx_err_logs)

    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)

    -- make sure no errors
    assert.logfile().has.no.line("[error]", true, 10)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)

  it("scrape response has metrics and comments only", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)

    for line in body:gmatch("[^\r\n]+") do
      assert.matches("^[#|kong]", line)
    end

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)

  it("exposes db reachability metrics", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_datastore_reachable 1', body, nil, true)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)

  it("exposes Lua worker VM stats", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_memory_workers_lua_vms_bytes{pid="%d+",kong_subsystem="http"} %d+', body)
    assert.matches('kong_memory_workers_lua_vms_bytes{pid="%d+",kong_subsystem="stream"} %d+', body)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)

  it("exposes lua_shared_dict metrics", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_memory_lua_shared_dict_total_bytes' ..
                   '{shared_dict="prometheus_metrics",kong_subsystem="http"} %d+', body)
    -- TODO: uncomment below once the ngx.shared iterrator in stream is fixed
    -- if stream_available then
    --   assert.matches('kong_memory_lua_shared_dict_total_bytes' ..
    --                 '{shared_dict="stream_prometheus_metrics",kong_subsystem="stream"} %d+', body)
    -- end

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)

  it("does not expose per consumer metrics by default", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.not_match('http_consumer_status', body, nil, true)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)
end)

describe("Plugin: prometheus (access) no stream listeners", function()
  local admin_client

  setup(function()
    local bp = helpers.get_db_utils()

    bp.plugins:insert {
      protocols = { "http", "https", "grpc", "grpcs", "tcp", "tls" },
      name = "prometheus"
    }

    assert(helpers.start_kong {
        plugins = "bundled, prometheus",
        stream_listen = "off",
    })
    admin_client = helpers.admin_client()
  end)

  teardown(function()
    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  it("exposes Lua worker VM stats only for http subsystem", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_memory_workers_lua_vms_bytes{pid="%d+",kong_subsystem="http"}', body)
    assert.not_matches('kong_memory_workers_lua_vms_bytes{pid="%d+",kong_subsystem="stream"}', body)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)

  it("exposes lua_shared_dict metrics only for http subsystem", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_memory_lua_shared_dict_total_bytes' ..
                   '{shared_dict="prometheus_metrics",kong_subsystem="http"} %d+', body)

    assert.not_matches('kong_memory_lua_shared_dict_bytes' ..
                   '{shared_dict="stream_prometheus_metric",kong_subsystem="stream"} %d+', body)
    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)
end)

describe("Plugin: prometheus (access) per-consumer metrics", function()
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

    local route = bp.routes:insert {
      protocols = { "http" },
      name = "http-route",
      paths = { "/" },
      methods = { "GET" },
      service = service,
    }

    bp.plugins:insert {
      protocols = { "http", "https", "grpc", "grpcs", "tcp", "tls" },
      name = "prometheus",
      config = {
        per_consumer = true,
      }
    }

    bp.plugins:insert {
      name  = "key-auth",
      route = route,
    }

    local consumer = bp.consumers:insert {
      username = "alice",
    }

    bp.keyauth_credentials:insert {
      key      = "alice-key",
      consumer = consumer,
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
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  it("increments the count for proxied requests", function()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/200",
      headers = {
        host = helpers.mock_upstream_host,
        apikey = 'alice-key',
      }
    })
    assert.res_status(200, res)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

      return body:find('kong_http_consumer_status{service="mock-service",route="http-route",code="200",consumer="alice"} 1', nil, true)
    end)

    res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/400",
      headers = {
        host = helpers.mock_upstream_host,
        apikey = 'alice-key',
      }
    })
    assert.res_status(400, res)

    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      local body = assert.res_status(200, res)
      assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

      return body:find('kong_http_consumer_status{service="mock-service",route="http-route",code="400",consumer="alice"} 1', nil, true)
    end)
  end)

  it("behave correctly if consumer is not found", function()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/200",
      headers = {
        host = helpers.mock_upstream_host,
      }
    })
    assert.res_status(401, res)

    local body
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      body = assert.res_status(200, res)
      return body:find('kong_http_status{service="mock-service",route="http-route",code="200"} 1', nil, true)
    end)

    assert.not_match('kong_http_consumer_status{service="mock-service",route="http-route",code="401",consumer="alice"} 1', body, nil, true)
    assert.matches('kong_http_status{service="mock-service",route="http-route",code="401"} 1', body, nil, true)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)
end)
