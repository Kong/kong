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
    end)
    it("compiles with custom conf", function()
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
  end)

  describe("compile_nginx_conf()", function()
    it("compile a main NGINX conf", function()
      local nginx_conf = nginx_conf_compiler.compile_nginx_conf(helpers.test_conf)
      assert.matches("worker_processes 1;", nginx_conf, nil, true)
      assert.matches("daemon on;", nginx_conf, nil, true)
    end)
    it("compiles with custom conf", function()
      local nginx_conf = nginx_conf_compiler.compile_nginx_conf(custom_conf)
      assert.matches("daemon off;", nginx_conf, nil, true)
    end)
  end)
end)
