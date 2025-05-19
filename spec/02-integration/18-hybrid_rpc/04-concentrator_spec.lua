local helpers = require "spec.helpers"


local function start_cp(strategy, prefix,
                        cluster_listen_port, admin_listen_port)
  assert(helpers.start_kong({
    role = "control_plane",
    database = strategy,
    prefix = prefix,
    cluster_cert = "spec/fixtures/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering.key",
    cluster_listen = "127.0.0.1:" .. cluster_listen_port,
    admin_listen = "127.0.0.1:" .. admin_listen_port,
    nginx_conf = "spec/fixtures/custom_nginx.template",

    nginx_worker_processes = 1,
    log_level = "debug",
    cluster_rpc = "on",
    plugins = "bundled,rpc-concentrator-test",
    cluster_rpc_sync = "off",
  }))
end


local function start_dp(prefix, cluster_listen_port)
  assert(helpers.start_kong({
    role = "data_plane",
    database = "off",
    prefix = prefix,
    cluster_cert = "spec/fixtures/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering.key",
    cluster_control_plane = "127.0.0.1:" .. cluster_listen_port,
    proxy_listen = "0.0.0.0:9002",
    nginx_conf = "spec/fixtures/custom_nginx.template",

    nginx_worker_processes = 4,
    log_level = "debug",
    cluster_rpc = "on",
    plugins = "bundled,rpc-concentrator-test",
    cluster_rpc_sync = "off",
  }))
end


-- register a test rpc service in custom plugin rpc-hello-test
for _, strategy in helpers.each_strategy() do
  describe("Hybrid Mode RPC over DB concentrator #" .. strategy, function()

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "clustering_data_planes",
      }) -- runs migrations

      -- 9005 is default cluster_listen_port
      -- 9001 is default admin_listen_port
      start_cp(strategy, "cp1",
               9005, 9001)

      start_dp("dp", 9005)
    end)

    lazy_teardown(function()
      helpers.stop_kong("dp")
      helpers.stop_kong("cp1")
    end)

    it("works well", function()
      local dp_logfile = "dp/logs/error.log"

      -- wait for rpc framework is ready
      assert.logfile(dp_logfile).has.line(
        "[kong.test.concentrator] rpc framework is ready.", true, 5)

      -- start a new cp node then call rpc via concentrator
      start_cp(strategy, "cp2",
               helpers.get_available_port(),
               helpers.get_available_port(),
               helpers.get_available_port())

      -- check dp's log
      assert.logfile(dp_logfile).has.line(
        "kong.test.concentrator: hello", true, 5)
      assert.logfile(dp_logfile).has.no.line(
        "[error]", true, 0)

      -- check cp's log

      local cp_logfile = "cp1/logs/error.log"

      assert.logfile(cp_logfile).has.line(
        "concentrator got 1 calls from database for node", true, 5)
      assert.logfile(cp_logfile).has.no.line(
        "assertion failed", true, 0)

      local cp_logfile = "cp2/logs/error.log"

      assert.logfile(cp_logfile).has.line(
        "[kong.test.concentrator] node_id: ", true, 5)
      assert.logfile(cp_logfile).has.line(
        "via concentrator", true, 5)
      assert.logfile(cp_logfile).has.line(
        "[rpc] kong.test.concentrator succeeded", true, 5)
      assert.logfile(cp_logfile).has.no.line(
        "via local", true, 0)
      assert.logfile(cp_logfile).has.no.line(
        "assertion failed", true, 0)
    end)
  end)
end -- for _, strategy
