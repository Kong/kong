local helpers = require "spec.helpers"
local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

local tcp_status_port = helpers.get_available_port()

for _, strategy in helpers.each_strategy() do
  describe("Plugin: prometheus, #" .. strategy, function()
    local status_client

    setup(function()
      assert(helpers.start_kong {
        -- nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
        database = strategy,
        cluster_cert = "spec/fixtures/ocsp_certs/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/ocsp_certs/kong_clustering.key",
        status_listen = "0.0.0.0:" .. tcp_status_port,
        db_update_propagation = 0.01, -- otherwise cassandra would complain
        proxy_listen = "0.0.0.0:8000",
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

    it("local and non-local metrics", function()
      local res = assert(status_client:send {
        method = "GET",
        path   = "/metrics",
      })
      local body = assert.res_status(200, res)

      assert.matches('kong_memory_lua_shared_dict_bytes', body, nil, true)

      local states = { "accepted", "active", "handled", "reading", "total", "waiting", "writing"}

      for _, v in ipairs(states) do
        assert.matches('kong_nginx_connections_total{node_id="' .. UUID_PATTERN .. '",subsystem="' .. ngx.config.subsystem .. '",state="' .. v .. '"} %d+', body)
      end

      local nonlocal = {
        "http_requests_total",
        "stream_sessions_total",
        "kong_latency_ms",
        "upstream_latency_ms",
        "request_latency_ms",
        "session_duration_ms",
        "bandwidth_bytes",
        "upstream_target_health",
        "data_plane_last_seen",
        "data_plane_config_hash",
        "data_plane_version_compatible",
        "data_plane_cluster_cert_expiry_timestamp",
      }

      for _, v in ipairs(nonlocal) do
        assert.not_matches('kong_' .. v, body, nil, true)
      end
    end)
  end)
end
