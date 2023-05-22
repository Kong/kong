-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

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
    assert.matches('kong_nginx_connections_total{node_id="' ..
      UUID_PATTERN .. '",subsystem="' .. ngx.config.subsystem .. '",state="' .. v .. '"} %d+', body)
  end
end

local high_cost_metrics = {
  "kong_http_requests_total",
  "kong_kong_latency_ms",
  "kong_upstream_latency_ms",
  "kong_request_latency_ms",
  "kong_bandwidth_bytes",
}


for _, strategy in helpers.each_strategy() do
  describe("Plugin: prometheus, on-demond export metrics #" .. strategy, function()
    local http_client, status_client
    local prometheus_id, ws_id

    -- restart the kong every time or the test would be flaky
    before_each(function()
      local bp = assert(helpers.get_db_utils(strategy, {
        "upstreams",
        "targets",
        "services",
        "routes",
        "plugins",
        "workspaces",
      }))

      -- to test if this works for EE
      local workspace = assert(bp.workspaces:insert {
        name = "test",
      })

      local upstream = bp.upstreams:insert_ws({
        name = "mock_upstream",
        algorithm = "least-connections",
      }, workspace)

      bp.targets:insert_ws({
        upstream = upstream,
        target = helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port,
        weight = 100,
      }, workspace)

      local service = bp.services:insert_ws({
        host = "mock_upstream",
      }, workspace)

      bp.routes:insert_ws({
        hosts     = { "mock" },
        protocols = { "http" },
        service   = service,
        paths     = { "/" },
      }, workspace)

      prometheus_id = assert(bp.plugins:insert_ws({
        name   = "prometheus",
        config = {
          status_code_metrics     = true,
          latency_metrics         = true,
          bandwidth_metrics       = true,
          upstream_health_metrics = true,
        }
      }, workspace)).id

      ws_id = workspace.name

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
        database = strategy,
        cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
        status_listen = "0.0.0.0:" .. tcp_status_port,
        proxy_listen = "0.0.0.0:8000",
        db_cache_ttl = 100, -- so the cache won't expire while we wait for the admin API
      })
      http_client = helpers.http_client("127.0.0.1", 8000, 20000)
      status_client = helpers.http_client("127.0.0.1", tcp_status_port, 20000)

      -- C* is so slow we need to wait
      helpers.pwait_until(function()
        assert.res_status(200, http_client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "mock"
          }
        })
      end, 10)
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
            path = "/" .. ws_id .. "/plugins/" .. prometheus_id,
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
            path = "/" .. ws_id .. "/plugins/" .. prometheus_id,
          })
        end

        helpers.pwait_until(function()
          body = get_metrics(status_client)
          assert_normal_metrics(body)

          for _, v in ipairs(high_cost_metrics) do
            assert.not_matches(v, body, nil, true)
          end
        end, 20)
      end)
    end
  end)
end
