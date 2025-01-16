local helpers = require "spec.helpers"


-- register a rpc connected event in custom plugin rpc-get-delta-test
-- ENABLE rpc sync on cp side for testing sync.v2.get_delta
-- DISABLE rpc sync on dp side
for _, strategy in helpers.each_strategy() do
  describe("Hybrid Mode RPC #" .. strategy, function()

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "clustering_data_planes",
      }) -- runs migrations

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled",
        nginx_worker_processes = 4, -- multiple workers
        cluster_rpc = "on", -- enable rpc
        cluster_rpc_sync = "on", -- enable rpc sync
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,rpc-get-delta-test",
        nginx_worker_processes = 4, -- multiple workers
        cluster_rpc = "on", -- enable rpc
        cluster_rpc_sync = "off", -- disable rpc sync
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("sync.v2.get_delta works", function()
      it("on cp side", function()
        local name = "servroot2/logs/error.log"

        -- dp logs
        assert.logfile(name).has.line(
          "kong.sync.v2.get_delta ok", true, 10)
        assert.logfile(name).has.no.line(
          "assertion failed", true, 0)
        assert.logfile(name).has.no.line(
          "[error]", true, 0)

        local name = nil

        -- cp logs
        assert.logfile(name).has.no.line(
          "assertion failed", true, 0)
        assert.logfile(name).has.no.line(
          "[error]", true, 0)

      end)
    end)
  end)
end -- for _, strategy
