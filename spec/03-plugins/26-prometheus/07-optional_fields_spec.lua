local helpers = require "spec.helpers"

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

      -- local metrics outputs
      assert.matches('kong_memory_lua_shared_dict_bytes', body, nil, true)
      assert.matches('kong_nginx_connections_total', body, nil, true)

      -- non-local metrics
      assert.not_matches('kong_nginx_metric_errors_total', body, nil, true)
    end)
  end)
end
