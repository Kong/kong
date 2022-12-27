local helpers = require "spec.helpers"

local tcp_status_port = helpers.get_available_port()


local function get_metrics(client)
  local res = assert(client:send {
    method = "GET",
    path   = "/metrics",
  })

  return assert.res_status(200, res)
end

local function assert_normal_metrics(body)
  -- normal fields
  assert.matches('kong_memory_lua_shared_dict_bytes', body, nil, true)
  local states = { "accepted", "active", "handled", "reading", "total", "waiting", "writing" }
  for _, v in ipairs(states) do
    assert.matches('kong_nginx_http_current_connections{state="' .. v .. '"} %d+', body)
  end
end

local high_cost_metrics = {
  "kong_bandwidth",
  "kong_latency_bucket",
  "kong_latency_count",
  "kong_latency_sum",
  "kong_nginx_metric_errors_total",
}


for _, strategy in helpers.each_strategy() do
  describe("Plugin: prometheus, on-demond export metrics #" .. strategy, function()
    local http_client, status_client
    local prometheus_id

    -- restart the kong every time or the test would be flaky
    before_each(function()
      local bp = assert(helpers.get_db_utils(strategy, {
        "plugins",
      }))

      local upstream = bp.upstreams:insert({
        name = "mock_upstream",
        algorithm = "least-connections",
      })

      bp.targets:insert({
        upstream = upstream,
        target = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port,
        weight = 100,
      })

      local service = bp.services:insert {
        host = "mock_upstream",
      }

      bp.routes:insert {
        hosts     = { "mock" },
        protocols = { "http" },
        service   = service,
        paths     = { "/" },
      }

      prometheus_id = assert(bp.plugins:insert {
        name   = "prometheus",
      }).id

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
        database = strategy,
        cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
        status_listen = "0.0.0.0:" .. tcp_status_port,
        db_update_propagation = 0.01, -- otherwise cassandra would complain
        proxy_listen = "0.0.0.0:8000",
        db_cache_ttl = 100, -- so the cache won't expire while we wait for the admin API
      })
      http_client = helpers.http_client("127.0.0.1", 8000, 20000)
      status_client = helpers.http_client("127.0.0.1", tcp_status_port, 20000)

      helpers.wait_until(function() return pcall(function()
        http_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "mock"
          }
        }
      end) end, 10)
    end)

    after_each(function()
      helpers.stop_kong()

      if http_client then
        http_client:close()
      end

      if status_client then
        status_client:close()
      end
    end)

    for _, method in ipairs { "disabling", "removing" } do
      it("less metrics when " .. method .. " prometheus", function()
        -- export normal metrics
        local body = get_metrics(status_client)
        assert_normal_metrics(body)
        for _, v in ipairs(high_cost_metrics) do
          assert.matches(v, body, nil, true)
        end

        -- disable or remove
        local admin_client = helpers.admin_client()
        if method == "disabling" then
          assert.res_status(200, admin_client:send {
            method = "PATCH",
            path = "/plugins/" .. prometheus_id,
            body = {
              enabled = false,
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })

        else
          assert.res_status(204, admin_client:send {
            method = "DELETE",
            path = "/plugins/" .. prometheus_id,
          })
        end

        helpers.wait_until(function() return pcall(function()
          body = get_metrics(status_client)
          assert_normal_metrics(body)

          for _, v in ipairs(high_cost_metrics) do
            assert.not_matches(v, body, nil, true)
          end
        end)end, 20)
      end)
    end
  end)
end
