local nginx_conf_compiler = require "kong.cmd.utils.nginx_conf_compiler"
local conf_loader = require "kong.conf_loader"
local helpers = require "spec.helpers"

describe("NGINX conf compiler", function()
  local custom_conf
  setup(function()
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
      local kong_nginx_conf = nginx_conf_compiler.compile_kong_conf(helpers.test_conf)
      assert.matches("lua_package_path '?/init.lua;./kong/?.lua;;';", kong_nginx_conf, nil, true)
      assert.matches("lua_code_cache on;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:9000;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:9001;", kong_nginx_conf, nil, true)
      assert.matches("server_name kong;", kong_nginx_conf, nil, true)
      assert.matches("server_name kong_admin;", kong_nginx_conf, nil, true)
      assert.not_matches("lua_ssl_trusted_certificate", kong_nginx_conf, nil, true)
    end)
    it("#only compiles with custom conf", function()
      local kong_nginx_conf = nginx_conf_compiler.compile_kong_conf(custom_conf)
      assert.matches("lua_code_cache off;", kong_nginx_conf, nil, true)
      assert.matches("lua_shared_dict cache 128k;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:80;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:8001;", kong_nginx_conf, nil, true)
    end)
    it("disables SSL", function()
      local kong_nginx_conf = nginx_conf_compiler.compile_kong_conf(custom_conf)
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
      local kong_nginx_conf = nginx_conf_compiler.compile_kong_conf(conf)
      assert.matches("lua_ssl_trusted_certificate '/path/to/ca.cert';", kong_nginx_conf, nil, true)
    end)
  end)

  describe("compile_nginx_conf()", function()
    it("compiles a main NGINX conf", function()
      local nginx_conf = nginx_conf_compiler.compile_nginx_conf(helpers.test_conf)
      assert.matches("worker_processes 1;", nginx_conf, nil, true)
      assert.matches("daemon on;", nginx_conf, nil, true)
    end)
    it("compiles with custom conf", function()
      local nginx_conf = nginx_conf_compiler.compile_nginx_conf(custom_conf)
      assert.matches("daemon off;", nginx_conf, nil, true)
    end)
    it("compiles without opinionated nginx optimizations", function()
      local conf = assert(conf_loader(nil, {
        nginx_optimizations = false,
      }))
      local nginx_conf = nginx_conf_compiler.compile_nginx_conf(conf)
      assert.not_matches("worker_connections %d+;", nginx_conf)
      assert.not_matches("multi_accept on;", nginx_conf)
    end)
    it("compiles with opinionated nginx optimizations", function()
      local conf = assert(conf_loader(nil, {
        nginx_optimizations = true,
      }))
      local nginx_conf = nginx_conf_compiler.compile_nginx_conf(conf)
      assert.matches("worker_connections %d+;", nginx_conf)
      assert.matches("multi_accept on;", nginx_conf)
    end)
  end)

  describe("prepare_prefix()", function()
    local prefix = "servroot_tmp"
    local pl_dir = require "pl.dir"
    local pl_path = require "pl.path"
    local exists, join = pl_path.exists, pl_path.join
    before_each(function()
      pcall(pl_dir.rmtree, prefix)
      pl_dir.makepath(prefix)
    end)
    after_each(function()
      pl_dir.rmtree(prefix)
    end)
    it("checks nginx_prefix exists", function()
      local ok, err = nginx_conf_compiler.prepare_prefix(helpers.test_conf, "./inexistent")
      assert.equal("./inexistent does not exist", err)
      assert.is_nil(ok)
    end)
    it("checks nginx_prefix is a directory", function()
      local tmp = os.tmpname()
      finally(function()
        assert(os.remove(tmp))
      end)
      local ok, err = nginx_conf_compiler.prepare_prefix(helpers.test_conf, tmp)
      assert.equal(tmp.." is not a directory", err)
      assert.is_nil(ok)
    end)
    it("creates NGINX conf and log files", function()
      assert(nginx_conf_compiler.prepare_prefix(helpers.test_conf, prefix))
      assert.truthy(exists(join(prefix, "nginx.conf")))
      assert.truthy(exists(join(prefix, "nginx-kong.conf")))
      assert.truthy(exists(join(prefix, "logs", "error.log")))
      assert.truthy(exists(join(prefix, "logs", "access.log")))
    end)
  end)
end)
