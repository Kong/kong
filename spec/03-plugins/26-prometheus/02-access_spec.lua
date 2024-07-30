local helpers = require "spec.helpers"
local shell = require "resty.shell"
local pl_file = require "pl.file"

local tcp_service_port = helpers.get_available_port()
local tcp_proxy_port = helpers.get_available_port()
local MOCK_PORT = helpers.get_available_port()
local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

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
      url = helpers.grpcbin_url,
    }

    bp.routes:insert {
      protocols = { "grpc" },
      name = "grpc-route",
      hosts = { "grpc" },
      service = grpc_service,
    }

    local grpcs_service = bp.services:insert {
      name = "mock-grpcs-service",
      url = helpers.grpcbin_ssl_url,
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
      name = "prometheus",
      config = {
        status_code_metrics = true,
        latency_metrics = true,
        bandwidth_metrics = true,
        upstream_health_metrics = true,
      },
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

      return body:find('http_requests_total{service="mock-service",route="http-route",code="200",source="service",workspace="default",consumer=""} 1', nil, true)
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

      return body:find('http_requests_total{service="mock-service",route="http-route",code="400",source="service",workspace="default",consumer=""} 1', nil, true)
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

      return body:find('http_requests_total{service="mock-grpc-service",route="grpc-route",code="200",source="service",workspace="default",consumer=""} 1', nil, true)
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

      return body:find('http_requests_total{service="mock-grpcs-service",route="grpcs-route",code="200",source="service",workspace="default",consumer=""} 1', nil, true)
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
      assert.matches('kong_stream_sessions_total{service="tcp-service",route="tcp-route",code="200",source="service",workspace="default"} 1', body, nil, true)
      assert.matches('kong_session_duration_ms_bucket{service="tcp%-service",route="tcp%-route",workspace="default",le="%+Inf"} %d+', body)

      return body:find('kong_stream_sessions_total{service="tcp-service",route="tcp-route",code="200",source="service",workspace="default"} 1', nil, true)
    end)

    thread:join()
  end)

  it("does not log error if no service was matched", function()
    -- cleanup logs
    shell.run(":> " .. helpers.test_conf.nginx_err_logs, nil, 0)

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
    shell.run(":> " .. helpers.test_conf.nginx_err_logs, nil, 0)

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
    assert.matches('kong_memory_workers_lua_vms_bytes{node_id="' .. UUID_PATTERN .. '",pid="%d+",kong_subsystem="http"} %d+', body)
    assert.matches('kong_memory_workers_lua_vms_bytes{node_id="' .. UUID_PATTERN .. '",pid="%d+",kong_subsystem="stream"} %d+', body)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)

  it("exposes lua_shared_dict metrics", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_memory_lua_shared_dict_total_bytes' ..
                   '{node_id="' .. UUID_PATTERN .. '",shared_dict="prometheus_metrics",kong_subsystem="http"} %d+', body)
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
      name = "prometheus",
      config = {
        status_code_metrics = true,
        latency_metrics = true,
        bandwidth_metrics = true,
        upstream_health_metrics = true,
      },
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
    assert.matches('kong_memory_workers_lua_vms_bytes{node_id="' .. UUID_PATTERN .. '",pid="%d+",kong_subsystem="http"}', body)
    assert.not_matches('kong_memory_workers_lua_vms_bytes{node_id="' .. UUID_PATTERN .. '",pid="%d+",kong_subsystem="stream"}', body)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)

  it("exposes lua_shared_dict metrics only for http subsystem", function()
    local res = assert(admin_client:send {
      method  = "GET",
      path    = "/metrics",
    })
    local body = assert.res_status(200, res)
    assert.matches('kong_memory_lua_shared_dict_total_bytes' ..
                   '{node_id="' .. UUID_PATTERN .. '",shared_dict="prometheus_metrics",kong_subsystem="http"} %d+', body)

    assert.not_matches('kong_memory_lua_shared_dict_bytes' ..
                   '{node_id="' .. UUID_PATTERN .. '",shared_dict="stream_prometheus_metric",kong_subsystem="stream"} %d+', body)
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
        status_code_metrics = true,
        latency_metrics = true,
        bandwidth_metrics = true,
        upstream_health_metrics = true,
      },
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

      return body:find('http_requests_total{service="mock-service",route="http-route",code="200",source="service",workspace="default",consumer="alice"} 1', nil, true)
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

      return body:find('http_requests_total{service="mock-service",route="http-route",code="400",source="service",workspace="default",consumer="alice"} 1', nil, true)
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
      return body:find('http_requests_total{service="mock-service",route="http-route",code="200",source="service",workspace="default",consumer="alice"} 1', nil, true)
    end)

    assert.matches('http_requests_total{service="mock-service",route="http-route",code="401",source="kong",workspace="default",consumer=""} 1', body, nil, true)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
  end)
end)

local granular_metrics_set = {
  status_code_metrics = "http_requests_total",
  latency_metrics = "kong_latency_ms",
  bandwidth_metrics = "bandwidth_bytes",
  upstream_health_metrics = "upstream_target_health",
}

for switch, expected_pattern in pairs(granular_metrics_set) do
describe("Plugin: prometheus (access) granular metrics switch", function()
  local proxy_client
  local admin_client

  local success_scrape = ""

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

    local upstream_hc_off = bp.upstreams:insert({
      name = "mock-upstream-healthchecksoff",
    })
    bp.targets:insert {
      target = helpers.mock_upstream_host .. ':' .. helpers.mock_upstream_port,
      weight = 1000,
      upstream = { id = upstream_hc_off.id },
    }

    bp.plugins:insert {
      protocols = { "http", "https", "grpc", "grpcs", "tcp", "tls" },
      name = "prometheus",
      config = {
        [switch] = true,
      },
    }

    assert(helpers.start_kong {
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled, prometheus",
      nginx_worker_processes = 1, -- due to healthcheck state flakyness and local switch of healthcheck export or not
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

  it("expected metrics " .. expected_pattern .. " is found", function()
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

      success_scrape = body

      return body:find(expected_pattern, nil, true)
    end)
  end)

  it("unexpected metrics is not found", function()
    for test_switch, test_expected_pattern in pairs(granular_metrics_set) do
      if test_switch ~= switch then
        assert.not_match(test_expected_pattern, success_scrape, nil, true)
      end
    end
  end)

end)
end

describe("Plugin: prometheus (access) AI metrics", function()
  local proxy_client
  local admin_client
  local prometheus_plugin

  setup(function()
    local bp = helpers.get_db_utils()

    local fixtures = {
      http_mock = {},
    }

    fixtures.http_mock.openai = [[
      server {
          server_name openai;
          listen ]]..MOCK_PORT..[[;
          
          default_type 'application/json';
    
  
          location = "/llm/v1/chat/good" {
            content_by_lua_block {
              local pl_file = require "pl.file"
              local json = require("cjson.safe")
  
              ngx.req.read_body()
              local body, err = ngx.req.get_body_data()
              body, err = json.decode(body)
  
              local token = ngx.req.get_headers()["authorization"]
              local token_query = ngx.req.get_uri_args()["apikey"]
  
              if token == "Bearer openai-key" or token_query == "openai-key" or body.apikey == "openai-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)
                
                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                else
                  ngx.status = 200
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/good.json"))
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
              end
            }
          }
      }
    ]]

    local empty_service = assert(bp.services:insert {
      name = "empty_service",
      host = "localhost", --helpers.mock_upstream_host,
      port = 8080, --MOCK_PORT,
      path = "/",
    })
  
    -- 200 chat good with one option
    local chat_good = assert(bp.routes:insert {
      service = empty_service,
      name = "http-route",
      protocols = { "http" },
      strip_path = true,
      paths = { "/" }
    })

    bp.plugins:insert {
      name = "ai-proxy",
      route = { id = chat_good.id },
      config = {
        route_type = "llm/v1/chat",
        logging = {
          log_payloads = false,
          log_statistics = true,
        },
        auth = {
          header_name = "Authorization",
          header_value = "Bearer openai-key",
        },
        model = {
          name = "gpt-3.5-turbo",
          provider = "openai",
          options = {
            max_tokens = 256,
            temperature = 1.0,
            upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good",
            input_cost = 10.0,
            output_cost = 10.0,
          },
        },
      },
    }

    prometheus_plugin = assert(bp.plugins:insert {
      protocols = { "http", "https", "grpc", "grpcs", "tcp", "tls" },
      name = "prometheus",
      config = {
        -- ai_metrics = true,
        status_code_metrics = true,
      },
    })

    assert(helpers.start_kong ({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled, prometheus",
    }, nil, nil, fixtures))
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

  it("no AI metrics when not enable in Prometheus plugin", function()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/200",
      headers = {
        host = helpers.mock_upstream_host,
        authorization = 'Bearer openai-key',
        ["content-type"] = 'application/json',
        accept = 'application/json',
      },
      body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
    })
    assert.res_status(200, res)

    local body
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      body = assert.res_status(200, res)
      return res.status == 200
    end)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
    assert.matches('http_requests_total{service="empty_service",route="http-route",code="200",source="service",workspace="default",consumer=""} 1', body, nil, true)
    
    assert.not_match('ai_llm_requests_total', body, nil, true)
    assert.not_match('ai_llm_cost_total', body, nil, true)
    assert.not_match('ai_llm_tokens_total', body, nil, true)
    assert.not_match('ai_llm_provider_latency_ms_bucket', body, nil, true)
  end)

  it("update prometheus plugin config", function()
    local body
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "PATCH",
        path = "/plugins/" .. prometheus_plugin.id,
        body = {
          name = "prometheus",
          config = {
            status_code_metrics = true,
            ai_metrics = true,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      body = assert.res_status(200, res)
      return res.status == 200
    end)

    local cjson = require "cjson"
    local json = cjson.decode(body)
    assert.equal(true, json.config.ai_metrics)

    ngx.sleep(2)
  end)
  
  it("add the count for proxied AI requests", function()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/200",
      headers = {
        host = helpers.mock_upstream_host,
        authorization = 'Bearer openai-key',
        ["content-type"] = 'application/json',
        accept = 'application/json',
      },
      body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
    })
    assert.res_status(200, res)

    local body
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      body = assert.res_status(200, res)
      return res.status == 200
    end)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
    assert.matches('http_requests_total{service="empty_service",route="http-route",code="200",source="service",workspace="default",consumer=""} 2', body, nil, true)
    
    assert.matches('ai_llm_requests_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default"} 1', body, nil, true)

    assert.matches('ai_llm_cost_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default"} 0.00037', body, nil, true)

    assert.matches('ai_llm_provider_latency_ms_bucket{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default",le="+Inf"} 1', body, nil, true)

    assert.matches('ai_llm_tokens_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",token_type="completion_tokens",workspace="default"} 12', body, nil, true)
    assert.matches('ai_llm_tokens_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",token_type="prompt_tokens",workspace="default"} 25', body, nil, true)
    assert.matches('ai_llm_tokens_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",token_type="total_tokens",workspace="default"} 37', body, nil, true)
  end)

  it("increments the count for proxied AI requests", function()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/200",
      headers = {
        host = helpers.mock_upstream_host,
        authorization = 'Bearer openai-key',
        ["content-type"] = 'application/json',
        accept = 'application/json',
      },
      body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
    })
    assert.res_status(200, res)

    local body
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      body = assert.res_status(200, res)
      return res.status == 200
    end)

    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)
    assert.matches('http_requests_total{service="empty_service",route="http-route",code="200",source="service",workspace="default",consumer=""} 3', body, nil, true)
    
    assert.matches('ai_llm_requests_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default"} 2', body, nil, true)

    assert.matches('ai_llm_cost_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default"} 0.00074', body, nil, true)

    assert.matches('ai_llm_provider_latency_ms_bucket{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default",le="+Inf"} 2', body, nil, true)

    assert.matches('ai_llm_tokens_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",token_type="completion_tokens",workspace="default"} 24', body, nil, true)
    assert.matches('ai_llm_tokens_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",token_type="prompt_tokens",workspace="default"} 50', body, nil, true)
    assert.matches('ai_llm_tokens_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",token_type="total_tokens",workspace="default"} 74', body, nil, true)
  end)

  it("behave correctly if AI metrics are not found", function()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/status/400",
      headers = {
        host = helpers.mock_upstream_host,
      }
    })
    assert.res_status(400, res)

    local body
    helpers.wait_until(function()
      local res = assert(admin_client:send {
        method  = "GET",
        path    = "/metrics",
      })
      body = assert.res_status(200, res)
      return res.status == 200
    end)

    assert.matches('http_requests_total{service="empty_service",route="http-route",code="400",source="kong",workspace="default",consumer=""} 1', body, nil, true)
    assert.matches('kong_nginx_metric_errors_total 0', body, nil, true)

    assert.matches('ai_llm_requests_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default"} 2', body, nil, true)
    assert.matches('ai_llm_cost_total{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default"} 0.00074', body, nil, true)
    assert.matches('ai_llm_provider_latency_ms_bucket{ai_provider="openai",ai_model="gpt-3.5-turbo",cache_status="",vector_db="",embeddings_provider="",embeddings_model="",workspace="default",le="+Inf"} 2', body, nil, true)
  end)
end)