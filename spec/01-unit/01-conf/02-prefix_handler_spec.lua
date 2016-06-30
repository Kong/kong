local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local prefix_handler = require "kong.cmd.utils.prefix_handler"

describe("NGINX conf compiler", function()
  local custom_conf
  setup(function()
    assert(prefix_handler.prepare_prefix(helpers.test_conf))

    custom_conf = assert(conf_loader(helpers.test_conf_path, {
      ssl = false,
      nginx_daemon = "off", -- false/off work
      lua_code_cache = false,
      mem_cache_size = "128k",
      proxy_listen = "0.0.0.0:80",
      admin_listen = "127.0.0.1:8001",
      proxy_listen_ssl = "0.0.0.0:443"
    }))
  end)

  describe("compile_kong_conf()", function()
    it("compiles the Kong NGINX conf chunk", function()
      local kong_nginx_conf = prefix_handler.compile_kong_conf(helpers.test_conf)
      assert.matches("lua_package_path '?/init.lua;./kong/?.lua;;';", kong_nginx_conf, nil, true)
      assert.matches("lua_code_cache on;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:9000;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:9001;", kong_nginx_conf, nil, true)
      assert.matches("server_name kong;", kong_nginx_conf, nil, true)
      assert.matches("server_name kong_admin;", kong_nginx_conf, nil, true)
      assert.not_matches("lua_ssl_trusted_certificate", kong_nginx_conf, nil, true)
    end)
    it("compiles with custom conf", function()
      local kong_nginx_conf = prefix_handler.compile_kong_conf(custom_conf)
      assert.matches("lua_code_cache off;", kong_nginx_conf, nil, true)
      assert.matches("lua_shared_dict cache 128k;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:80;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:8001;", kong_nginx_conf, nil, true)
    end)
    it("disables SSL", function()
      local kong_nginx_conf = prefix_handler.compile_kong_conf(custom_conf)
      assert.not_matches("listen %d+%.%d+%.%d+%.%d+:%d+ ssl;", kong_nginx_conf)
      assert.not_matches("ssl_certificate", kong_nginx_conf)
      assert.not_matches("ssl_certificate_key", kong_nginx_conf)
      assert.not_matches("ssl_protocols", kong_nginx_conf)
      assert.not_matches("ssl_certificate_by_lua_block", kong_nginx_conf)
    end)
    it("sets lua_ssl_trusted_certificate", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        cassandra_ssl = true,
        cassandra_ssl_trusted_cert = "/path/to/ca.cert"
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("lua_ssl_trusted_certificate '/path/to/ca.cert';", kong_nginx_conf, nil, true)
    end)
  end)

  describe("compile_nginx_conf()", function()
    it("compiles a main NGINX conf", function()
      local nginx_conf = prefix_handler.compile_nginx_conf(helpers.test_conf)
      assert.matches("worker_processes 1;", nginx_conf, nil, true)
      assert.matches("daemon on;", nginx_conf, nil, true)
    end)
    it("compiles with custom conf", function()
      local nginx_conf = prefix_handler.compile_nginx_conf(custom_conf)
      assert.matches("daemon off;", nginx_conf, nil, true)
    end)
    it("compiles without opinionated nginx optimizations", function()
      local conf = assert(conf_loader(nil, {
        nginx_optimizations = false,
      }))

      local nginx_conf = prefix_handler.compile_nginx_conf(conf)
      assert.not_matches("worker_rlimit_nofile %d+;", nginx_conf)
      assert.not_matches("worker_connections %d+;", nginx_conf)
      assert.not_matches("multi_accept on;", nginx_conf)
    end)
    it("compiles with opinionated nginx optimizations", function()
      local conf = assert(conf_loader(nil, {
        nginx_optimizations = true,
      }))
      local nginx_conf = prefix_handler.compile_nginx_conf(conf)
      assert.matches("worker_rlimit_nofile %d+;", nginx_conf)
      assert.matches("worker_connections %d+;", nginx_conf)
      assert.matches("multi_accept on;", nginx_conf)
    end)
    it("compiles without anonymous reports", function()
      local conf = assert(conf_loader(nil, {
        anonymous_reports = false,
      }))
      local nginx_conf = prefix_handler.compile_nginx_conf(conf)
      assert.not_matches("error_log syslog:server=.+ error;", nginx_conf)
    end)
    it("compiles with anonymous reports", function()
      local conf = assert(conf_loader(nil, {
        anonymous_reports = true,
      }))
      local nginx_conf = prefix_handler.compile_nginx_conf(conf)
      assert.matches("error_log syslog:server=.+:61828 error;", nginx_conf)
    end)
  end)

  describe("prepare_prefix()", function()
    local exists, join = helpers.path.exists, helpers.path.join
    local tmp_config = conf_loader(helpers.test_conf_path, {
      prefix = "servroot_tmp"
    })

    before_each(function()
      pcall(helpers.dir.rmtree, tmp_config.prefix)
      helpers.dir.makepath(tmp_config.prefix)
    end)
    after_each(function()
      pcall(helpers.dir.rmtree, tmp_config.prefix)
    end)

    it("creates inexistent prefix", function()
      finally(function()
        pcall(helpers.dir.rmtree, "inexistent")
      end)

      local config = assert(conf_loader(helpers.test_conf_path, {
        prefix = "inexistent"
      }))
      assert(prefix_handler.prepare_prefix(config))
      assert.truthy(exists("inexistent"))
    end)
    it("checks prefix is a directory", function()
      local tmp = os.tmpname()
      finally(function()
        os.remove(tmp)
      end)

      local config = assert(conf_loader(helpers.test_conf_path, {
        prefix = tmp
      }))
      local ok, err = prefix_handler.prepare_prefix(config)
      assert.equal(tmp.." is not a directory", err)
      assert.is_nil(ok)
    end)
    it("creates pids folder", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      assert.truthy(exists(join(tmp_config.prefix, "pids")))
    end)
    it("creates serf folder", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      assert.truthy(exists(join(tmp_config.prefix, "serf")))
    end)
    it("creates NGINX conf and log files", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      assert.truthy(exists(tmp_config.kong_conf))
      assert.truthy(exists(tmp_config.nginx_kong_conf))
      assert.truthy(exists(tmp_config.nginx_err_logs))
      assert.truthy(exists(tmp_config.nginx_acc_logs))
    end)
    it("dumps Kong conf", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      local in_prefix_kong_conf = assert(conf_loader(tmp_config.kong_conf))
      assert.same(tmp_config, in_prefix_kong_conf)
    end)
    it("dump Kong conf (custom conf)", function()
      local conf = assert(conf_loader(nil, {
        pg_database = "foobar",
        prefix = tmp_config.prefix
      }))
      assert.equal("foobar", conf.pg_database)
      assert(prefix_handler.prepare_prefix(conf))
      local in_prefix_kong_conf = assert(conf_loader(tmp_config.kong_conf))
      assert.same(conf, in_prefix_kong_conf)
    end)
    it("dumps Serf script", function()
      assert(prefix_handler.prepare_prefix(tmp_config))

      local identifier = helpers.file.read(tmp_config.serf_event)
      assert.is_string(identifier)
    end)
    it("dumps Serf identifier", function()
      assert(prefix_handler.prepare_prefix(tmp_config))

      local identifier = helpers.file.read(tmp_config.serf_node_id)
      assert.is_string(identifier)
    end)
    it("preserves Serf identifier if already exists", function()
      -- prepare twice
      assert(prefix_handler.prepare_prefix(tmp_config))
      local identifier_1 = helpers.file.read(tmp_config.serf_node_id)

      assert(prefix_handler.prepare_prefix(tmp_config))
      local identifier_2 = helpers.file.read(tmp_config.serf_node_id)

      assert.equal(identifier_1, identifier_2)
    end)
  end)
end)

