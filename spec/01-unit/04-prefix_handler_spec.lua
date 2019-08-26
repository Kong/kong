local helpers = require "spec.helpers"
local conf_loader = require "kong.conf_loader"
local prefix_handler = require "kong.cmd.utils.prefix_handler"

local exists = helpers.path.exists
local join = helpers.path.join

describe("NGINX conf compiler", function()
  describe("gen_default_ssl_cert()", function()
    local conf = assert(conf_loader(helpers.test_conf_path, {
      prefix = "ssl_tmp",
      ssl_cert = "spec/fixtures/kong_spec.crt",
      ssl_cert_key = "spec/fixtures/kong_spec.key",
      admin_ssl_cert = "spec/fixtures/kong_spec.crt",
      admin_ssl_cert_key = "spec/fixtures/kong_spec.key",
    }))
    before_each(function()
      helpers.dir.makepath("ssl_tmp")
    end)
    after_each(function()
      pcall(helpers.dir.rmtree, "ssl_tmp")
    end)
    describe("proxy", function()
      it("auto-generates SSL certificate and key", function()
        assert(prefix_handler.gen_default_ssl_cert(conf, "default"))
        assert(exists(conf.ssl_cert_default))
        assert(exists(conf.ssl_cert_key_default))
      end)
      it("does not re-generate if they already exist", function()
        assert(prefix_handler.gen_default_ssl_cert(conf, "default"))
        local cer = helpers.file.read(conf.ssl_cert_default)
        local key = helpers.file.read(conf.ssl_cert_key_default)
        assert(prefix_handler.gen_default_ssl_cert(conf, "default"))
        assert.equal(cer, helpers.file.read(conf.ssl_cert_default))
        assert.equal(key, helpers.file.read(conf.ssl_cert_key_default))
      end)
    end)
    describe("admin", function()
      it("auto-generates SSL certificate and key", function()
        assert(prefix_handler.gen_default_ssl_cert(conf, "admin"))
        assert(exists(conf.admin_ssl_cert_default))
        assert(exists(conf.admin_ssl_cert_key_default))
      end)
      it("does not re-generate if they already exist", function()
        assert(prefix_handler.gen_default_ssl_cert(conf, "admin"))
        local cer = helpers.file.read(conf.admin_ssl_cert_default)
        local key = helpers.file.read(conf.admin_ssl_cert_key_default)
        assert(prefix_handler.gen_default_ssl_cert(conf, "admin"))
        assert.equal(cer, helpers.file.read(conf.admin_ssl_cert_default))
        assert.equal(key, helpers.file.read(conf.admin_ssl_cert_key_default))
      end)
    end)
  end)

  describe("#stream compile_kong_stream_conf()", function()
    it("enables ssl_preread conditionally", function()
      local save_nginx_configure = ngx.config.nginx_configure -- luacheck: ignore
      finally(function()
        ngx.config.nginx_configure = save_nginx_configure -- luacheck: ignore
      end)

      -- with ssl_preread enabled
      ngx.config.nginx_configure = function() -- luacheck: ignore
        return "--with-foo --with-stream_ssl_preread_module --with-bar"
      end
      local conf = assert(conf_loader(helpers.test_conf_path, {
        stream_listen = "0.0.0.0:9100",
      }))
      local kong_nginx_stream_conf = prefix_handler.compile_kong_stream_conf(conf)
      assert.matches("ssl_preread on", kong_nginx_stream_conf, nil, true)

      -- without ssl_preread enabled
      ngx.config.nginx_configure = function() -- luacheck: ignore
        return " --with-foo --with-bar"
      end
      conf = assert(conf_loader(helpers.test_conf_path, {
        stream_listen = "0.0.0.0:9100",
      }))
      kong_nginx_stream_conf = prefix_handler.compile_kong_stream_conf(conf)
      assert.not_matches("ssl_preread on", kong_nginx_stream_conf, nil, true)
    end)
  end)

  describe("compile_kong_conf()", function()
    it("compiles the Kong NGINX conf chunk", function()
      local kong_nginx_conf = prefix_handler.compile_kong_conf(helpers.test_conf)
      assert.matches("lua_package_path './spec/fixtures/custom_plugins/?.lua;;'", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:9000;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:9001;", kong_nginx_conf, nil, true)
      assert.matches("server_name kong;", kong_nginx_conf, nil, true)
      assert.matches("server_name kong_admin;", kong_nginx_conf, nil, true)
      assert.not_matches("lua_ssl_trusted_certificate", kong_nginx_conf, nil, true)
    end)
    it("compiles with custom conf", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        mem_cache_size = "128k",
        proxy_listen = "0.0.0.0:80",
        admin_listen = "127.0.0.1:8001"
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("lua_shared_dict kong_db_cache%s+128k;", kong_nginx_conf)
      assert.matches("listen 0.0.0.0:80;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:8001;", kong_nginx_conf, nil, true)
    end)
    it("enables HTTP/2", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        proxy_listen = "0.0.0.0:9000, 0.0.0.0:9443 http2 ssl",
        admin_listen = "127.0.0.1:9001, 127.0.0.1:9444 http2 ssl",
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("listen 0.0.0.0:9000;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:9443 ssl http2;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:9001;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:9444 ssl http2;", kong_nginx_conf, nil, true)

      conf = assert(conf_loader(helpers.test_conf_path, {
        proxy_listen = "0.0.0.0:9000, 0.0.0.0:9443 http2 ssl",
        admin_listen = "127.0.0.1:9001, 127.0.0.1:8444 ssl",
      }))
      kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("listen 0.0.0.0:9000;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:9443 ssl http2;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:9001;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:8444 ssl;", kong_nginx_conf, nil, true)

      conf = assert(conf_loader(helpers.test_conf_path, {
        proxy_listen = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
        admin_listen = "127.0.0.1:9001, 127.0.0.1:8444 http2 ssl",
      }))
      kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("listen 0.0.0.0:9000;", kong_nginx_conf, nil, true)
      assert.matches("listen 0.0.0.0:9443 ssl;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:9001;", kong_nginx_conf, nil, true)
      assert.matches("listen 127.0.0.1:8444 ssl http2;", kong_nginx_conf, nil, true)
    end)
    it("enables proxy_protocol", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        proxy_listen = "0.0.0.0:9000 proxy_protocol",
        real_ip_header = "proxy_protocol",
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("listen 0.0.0.0:9000 proxy_protocol;", kong_nginx_conf, nil, true)
      assert.matches("real_ip_header%s+proxy_protocol;", kong_nginx_conf)
    end)
    it("enables deferred", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        proxy_listen = "0.0.0.0:9000 deferred",
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("listen 0.0.0.0:9000 deferred;", kong_nginx_conf, nil, true)
    end)
    it("enables bind", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        proxy_listen = "0.0.0.0:9000 bind",
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("listen 0.0.0.0:9000 bind;", kong_nginx_conf, nil, true)
    end)
    it("enables reuseport", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        proxy_listen = "0.0.0.0:9000 reuseport",
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("listen 0.0.0.0:9000 reuseport;", kong_nginx_conf, nil, true)
    end)
    it("disables SSL", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        proxy_listen = "127.0.0.1:8000",
        admin_listen = "127.0.0.1:8001",
        admin_gui_listen = "0.0.0.0:9002",
        portal_gui_listen = "0.0.0.0:9003",
        portal_api_listen = "0.0.0.0:9004",
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.not_matches("listen %d+%.%d+%.%d+%.%d+:%d+ ssl;", kong_nginx_conf)
      assert.not_matches("ssl_certificate", kong_nginx_conf)
      assert.not_matches("ssl_certificate_key", kong_nginx_conf)
      assert.not_matches("ssl_protocols", kong_nginx_conf)
      assert.not_matches("ssl_certificate_by_lua_block", kong_nginx_conf)
    end)
    describe("handles client_ssl", function()
      it("on", function()
        local conf = assert(conf_loader(helpers.test_conf_path, {
          client_ssl = true,
          client_ssl_cert = "spec/fixtures/kong_spec.crt",
          client_ssl_cert_key = "spec/fixtures/kong_spec.key",
        }))
        local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("proxy_ssl_certificate.*spec/fixtures/kong_spec.crt", kong_nginx_conf)
        assert.matches("proxy_ssl_certificate_key.*spec/fixtures/kong_spec.key", kong_nginx_conf)
      end)
      it("off", function()
        local conf = assert(conf_loader(helpers.test_conf_path, {
          client_ssl = false,
        }))
        local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.not_matches("proxy_ssl_certificate.*spec/fixtures/kong_spec.crt", kong_nginx_conf)
        assert.not_matches("proxy_ssl_certificate_key.*spec/fixtures/kong_spec.key", kong_nginx_conf)
      end)
    end)
    it("sets lua_ssl_verify_depth", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        lua_ssl_verify_depth = "2"
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("lua_ssl_verify_depth 2;", kong_nginx_conf, nil, true)
    end)
    it("includes default lua_ssl_verify_depth", function()
      local conf = assert(conf_loader(helpers.test_conf_path))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("lua_ssl_verify_depth 1;", kong_nginx_conf, nil, true)
    end)
    it("does not include lua_ssl_trusted_certificate by default", function()
      local conf = assert(conf_loader(helpers.test_conf_path))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.not_matches("lua_ssl_trusted_certificate", kong_nginx_conf, nil, true)
    end)
    it("sets lua_ssl_trusted_certificate", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        lua_ssl_trusted_certificate = "/path/to/ca.cert",
      }))
      local kong_nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("lua_ssl_trusted_certificate '/path/to/ca.cert';", kong_nginx_conf, nil, true)
    end)
    it("compiles without anonymous reports", function()
      local conf = assert(conf_loader(nil, {
        anonymous_reports = false,
      }))
      local nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.not_matches("error_log syslog:server=.+ error;", nginx_conf)
    end)
    it("compiles with anonymous reports", function()
      local conf = assert(conf_loader(nil, {
        anonymous_reports = true,
      }))
      local nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("error_log syslog:server=.+:61828 error;", nginx_conf)
    end)
    it("defines the client_max_body_size by default", function()
      local conf = assert(conf_loader(nil, {}))
      local nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("client_max_body_size 0", nginx_conf, nil, true)
    end)
    it("writes the client_max_body_size as defined", function()
      local conf = assert(conf_loader(nil, {
        client_max_body_size = "1m",
      }))
      local nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("client_max_body_size 1m", nginx_conf, nil, true)
    end)
    it("defines the client_body_buffer_size directive by default", function()
      local conf = assert(conf_loader(nil, {}))
      local nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("client_body_buffer_size 8k", nginx_conf, nil, true)
    end)
    it("writes the client_body_buffer_size directive as defined", function()
      local conf = assert(conf_loader(nil, {
        client_body_buffer_size = "128k",
      }))
      local nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("client_body_buffer_size 128k", nginx_conf, nil, true)
    end)
    it("writes kong_cassandra shm if using Cassandra", function()
      local conf = assert(conf_loader(nil, {
        database = "cassandra",
      }))
      local nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.matches("lua_shared_dict%s+kong_cassandra", nginx_conf)
    end)
    it("does not write kong_cassandra shm if not using Cassandra", function()
      local conf = assert(conf_loader(nil, {
        database = "postgres",
      }))
      local nginx_conf = prefix_handler.compile_kong_conf(conf)
      assert.not_matches("lua_shared_dict%s+kong_cassandra", nginx_conf)
    end)

    describe("user directive", function()
      it("is not included by default", function()
        local conf = assert(conf_loader(helpers.test_conf_path))
        local nginx_conf = prefix_handler.compile_nginx_conf(conf)
        assert.not_matches("user[^;]*;", nginx_conf, nil, true)
      end)
      it("is not included when 'nobody'", function()
        local conf = assert(conf_loader(helpers.test_conf_path, {
          nginx_user = "nobody"
        }))
        local nginx_conf = prefix_handler.compile_nginx_conf(conf)
        assert.not_matches("user[^;]*;", nginx_conf, nil, true)
      end)
      it("is not included when 'nobody nobody'", function()
        local conf = assert(conf_loader(helpers.test_conf_path, {
          nginx_user = "nobody nobody"
        }))
        local nginx_conf = prefix_handler.compile_nginx_conf(conf)
        assert.not_matches("user[^;]*;", nginx_conf, nil, true)
      end)
      it("is included when otherwise", function()
        local conf = assert(conf_loader(helpers.test_conf_path, {
          nginx_user = "www_data www_data"
        }))
        local nginx_conf = prefix_handler.compile_nginx_conf(conf)
        assert.matches("user www_data www_data;", nginx_conf, nil, true)
      end)
    end)

    describe("ngx_http_realip_module settings", function()
      it("defaults", function()
        local conf = assert(conf_loader())
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("real_ip_header%s+X%-Real%-IP;", nginx_conf)
        assert.matches("real_ip_recursive%s+off;", nginx_conf)
        assert.not_matches("set_real_ip_from", nginx_conf)
      end)

      it("real_ip_recursive on", function()
        local conf = assert(conf_loader(nil, {
          real_ip_recursive = true,
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("real_ip_recursive%s+on;", nginx_conf)
      end)

      it("real_ip_recursive off", function()
        local conf = assert(conf_loader(nil, {
          real_ip_recursive = false,
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("real_ip_recursive%s+off;", nginx_conf)
      end)

      it("set_real_ip_from", function()
        local conf = assert(conf_loader(nil, {
          trusted_ips = "192.168.1.0/24,192.168.2.1,2001:0db8::/32"
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("set_real_ip_from%s+192.168.1.0/24", nginx_conf)
        assert.matches("set_real_ip_from%s+192.168.1.0",    nginx_conf)
        assert.matches("set_real_ip_from%s+2001:0db8::/32", nginx_conf)
      end)
      it("set_real_ip_from (stream proxy)", function()
        local conf = assert(conf_loader(nil, {
          trusted_ips = "192.168.1.0/24,192.168.2.1,2001:0db8::/32"
        }))
        local nginx_conf = prefix_handler.compile_kong_stream_conf(conf)
        assert.matches("set_real_ip_from%s+192.168.1.0/24", nginx_conf)
        assert.matches("set_real_ip_from%s+192.168.1.0",    nginx_conf)
        assert.matches("set_real_ip_from%s+2001:0db8::/32", nginx_conf)
      end)
      it("proxy_protocol", function()
        local conf = assert(conf_loader(nil, {
          proxy_listen = "0.0.0.0:8000 proxy_protocol, 0.0.0.0:8443 ssl",
          real_ip_header = "proxy_protocol",
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("real_ip_header%s+proxy_protocol", nginx_conf)
        assert.matches("listen 0.0.0.0:8000 proxy_protocol;", nginx_conf)
        assert.matches("listen 0.0.0.0:8443 ssl;", nginx_conf)
      end)
    end)

    describe("injected NGINX directives", function()
      it("injects ngx_http_* directives", function()
        local conf = assert(conf_loader(nil, {
          nginx_http_large_client_header_buffers = "8 24k",
          nginx_http_log_format = "custom_fmt '$connection $request_time'"
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("large_client_header_buffers%s+8 24k;", nginx_conf)
        assert.matches("log_format custom_fmt '$connection $request_time';",
                       nginx_conf, nil, true)
      end)

      it("injects ngx_proxy_* directives", function()
        local conf = assert(conf_loader(nil, {
          nginx_http_large_client_header_buffers = "16 24k",
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("large_client_header_buffers%s+16 24k;", nginx_conf)
      end)

      it("injects ngx_admin_* directives", function()
        local conf = assert(conf_loader(nil, {
          nginx_http_large_client_header_buffers = "4 24k",
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("large_client_header_buffers%s+4 24k;", nginx_conf)
      end)

      it("injects nginx_http_upstream_* directives", function()
        local conf = assert(conf_loader(nil, {
          nginx_http_upstream_keepalive = "120",
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.matches("keepalive 120;", nginx_conf, nil, true)
      end)

      it("does not inject directives if value is 'NONE'", function()
        local conf = assert(conf_loader(nil, {
          nginx_http_upstream_keepalive = "NONE",
        }))
        local nginx_conf = prefix_handler.compile_kong_conf(conf)
        assert.not_matches("keepalive %d+;", nginx_conf)
      end)

      describe("default injected NGINX directives", function()
        it("configures default http upstream{} block directives", function()
          local conf = assert(conf_loader())
          local nginx_conf = prefix_handler.compile_kong_conf(conf)
          assert.matches("keepalive 60;", nginx_conf, nil, true)
          assert.matches("keepalive_requests 100;", nginx_conf, nil, true)
          assert.matches("keepalive_timeout 60s;", nginx_conf, nil, true)
        end)
      end)
    end)
  end)

  describe("compile_nginx_conf()", function()
    it("compiles a main NGINX conf", function()
      local nginx_conf = prefix_handler.compile_nginx_conf(helpers.test_conf)
      assert.matches("worker_processes 1;", nginx_conf, nil, true)
      assert.matches("daemon on;", nginx_conf, nil, true)
    end)
    it("compiles with custom conf", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        nginx_daemon = "off"
      }))
      local nginx_conf = prefix_handler.compile_nginx_conf(conf)
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
    it("converts dns_resolver to string", function()
      local nginx_conf = prefix_handler.compile_nginx_conf({
        dns_resolver = { "8.8.8.8", "8.8.4.4" }
      }, [[
        "resolver ${{DNS_RESOLVER}} ipv6=off;"
      ]])
      assert.matches("resolver 8.8.8.8 8.8.4.4 ipv6=off;", nginx_conf, nil, true)
    end)
  end)

  describe("prepare_prefix()", function()
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
    it("ensures prefix is a directory", function()
      local tmp = os.tmpname()
      finally(function()
        os.remove(tmp)
      end)

      local config = assert(conf_loader(helpers.test_conf_path, {
        prefix = tmp
      }))
      local ok, err = prefix_handler.prepare_prefix(config)
      assert.equal(tmp .. " is not a directory", err)
      assert.is_nil(ok)
    end)
    it("creates pids folder", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      assert.truthy(exists(join(tmp_config.prefix, "pids")))
    end)
    it("creates NGINX conf and log files", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      assert.truthy(exists(tmp_config.kong_env))
      assert.truthy(exists(tmp_config.nginx_kong_conf))
      assert.truthy(exists(tmp_config.nginx_err_logs))
      assert.truthy(exists(tmp_config.nginx_acc_logs))
      assert.truthy(exists(tmp_config.admin_acc_logs))
    end)
    it("dumps Kong conf", function()
      assert(prefix_handler.prepare_prefix(tmp_config))
      local in_prefix_kong_conf = assert(conf_loader(tmp_config.kong_env))
      assert.same(tmp_config, in_prefix_kong_conf)
    end)
    it("dump Kong conf (custom conf)", function()
      local conf = assert(conf_loader(nil, {
        pg_database = "foobar",
        pg_schema   = "foo",
        prefix = tmp_config.prefix
      }))
      assert.equal("foobar", conf.pg_database)
      assert.equal("foo", conf.pg_schema)
      assert(prefix_handler.prepare_prefix(conf))
      local in_prefix_kong_conf = assert(conf_loader(tmp_config.kong_env, {
        pg_database = "foobar",
        pg_schema = "foo",
        prefix = tmp_config.prefix,
      }))

      -- Workaround for random iteration of pairs in find_dynamic_keys
      table.sort(conf.nginx_http_upstream_directives,
        function(a, b) return a.name <= b.name end)
      table.sort(in_prefix_kong_conf.nginx_http_upstream_directives,
        function(a, b) return a.name <= b.name end)

      assert.same(conf, in_prefix_kong_conf)
    end)
    it("writes custom plugins in Kong conf", function()
      local conf = assert(conf_loader(nil, {
        plugins = { "foo", "bar" },
        prefix = tmp_config.prefix
      }))

      assert(prefix_handler.prepare_prefix(conf))

      local in_prefix_kong_conf = assert(conf_loader(tmp_config.kong_env))
      assert.True(in_prefix_kong_conf.loaded_plugins.foo)
      assert.True(in_prefix_kong_conf.loaded_plugins.bar)
    end)

    describe("ssl", function()
      it("does not create SSL dir if disabled", function()
        local conf = conf_loader(nil, {
          prefix = tmp_config.prefix,
          proxy_listen = "127.0.0.1:8000",
          admin_listen = "127.0.0.1:8001",
          admin_gui_listen = "0.0.0.0:9002",
          portal_gui_listen = "0.0.0.0:9003",
          portal_api_listen = "0.0.0.0:9004",
        })

        assert(prefix_handler.prepare_prefix(conf))
        assert.falsy(exists(join(conf.prefix, "ssl")))
      end)
      it("does not create SSL dir if using custom cert", function()
        local conf = conf_loader(nil, {
          prefix = tmp_config.prefix,
          proxy_listen = "127.0.0.1:8000 ssl",
          admin_listen = "127.0.0.1:8001 ssl",
          ssl_cert = "spec/fixtures/kong_spec.crt",
          ssl_cert_key = "spec/fixtures/kong_spec.key",
          admin_ssl_cert = "spec/fixtures/kong_spec.crt",
          admin_ssl_cert_key = "spec/fixtures/kong_spec.key",
          admin_gui_listen = "0.0.0.0:9002, 0.0.0.0:9445 ssl",
          admin_gui_ssl_cert = "spec/fixtures/kong_spec.crt",
          admin_gui_ssl_cert_key = "spec/fixtures/kong_spec.key",
          portal_gui_listen = "0.0.0.0:9003, 0.0.0.0:9446 ssl",
          portal_gui_ssl_cert = "spec/fixtures/kong_spec.crt",
          portal_gui_ssl_cert_key = "spec/fixtures/kong_spec.key",
          portal_api_listen = "0.0.0.0:9004, 0.0.0.0:9447 ssl",
          portal_api_ssl_cert = "spec/fixtures/kong_spec.crt",
          portal_api_ssl_cert_key = "spec/fixtures/kong_spec.key",
        })

        assert(prefix_handler.prepare_prefix(conf))
        assert.falsy(exists(join(conf.prefix, "ssl")))
      end)
      it("generates default SSL cert", function()
        local conf = conf_loader(nil, {
          prefix = tmp_config.prefix,
          proxy_listen = "127.0.0.1:8000 ssl",
          admin_listen = "127.0.0.1:8001 ssl",
        })

        assert(prefix_handler.prepare_prefix(conf))
        assert.truthy(exists(join(conf.prefix, "ssl")))
        assert.truthy(exists(conf.ssl_cert_default))
        assert.truthy(exists(conf.ssl_cert_key_default))
        assert.truthy(exists(conf.admin_ssl_cert_default))
        assert.truthy(exists(conf.admin_ssl_cert_key_default))
      end)
    end)

    describe("custom template", function()
      local templ_fixture = "spec/fixtures/custom_nginx.template"

      it("accepts a custom NGINX conf template", function()
        assert(prefix_handler.prepare_prefix(tmp_config, templ_fixture))
        assert.truthy(exists(tmp_config.nginx_conf))

        local contents = helpers.file.read(tmp_config.nginx_conf)
        assert.matches("# This is a custom nginx configuration template for Kong specs", contents, nil, true)
        assert.matches("daemon on;", contents, nil, true)
        assert.matches("listen 0.0.0.0:9000;", contents, nil, true)
      end)
      it("errors on non-existing file", function()
        local ok, err = prefix_handler.prepare_prefix(tmp_config, "spec/fixtures/inexistent.template")
        assert.is_nil(ok)
        assert.equal("no such file: spec/fixtures/inexistent.template", err)
      end)
      it("reports Penlight templating errors", function()
        local u = helpers.unindent
        local tmp = os.tmpname()

        helpers.file.write(tmp, u[[
          > if t.hello then

          > end
        ]])

        finally(function()
          helpers.file.delete(tmp)
        end)

        local ok, err = prefix_handler.prepare_prefix(helpers.test_conf, tmp)
        assert.is_nil(ok)
        assert.matches("failed to compile nginx config template: .* " ..
                       "attempt to index global 't' %(a nil value%)", err)
      end)
    end)

    describe("nginx_* injected directives aliases", function()
      -- Aliases maintained for pre-established Nginx directives specified
      -- as Kong config properties

      describe("'upstream_keepalive'", function()

        describe("1.2 Nginx template", function()
          local templ_fixture = "spec/fixtures/1.2_custom_nginx.template"

          it("compiles", function()
            assert(prefix_handler.prepare_prefix(tmp_config, templ_fixture))
            assert.truthy(exists(tmp_config.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("# This is the Kong 1.2 default template", contents,
                           nil, true)
            assert.matches("daemon on;", contents, nil, true)
            assert.matches("listen 0.0.0.0:9000;", contents, nil, true)
            assert.matches("keepalive 60;", contents, nil, true)
          end)

          it("'upstream_keepalive = 0' disables keepalive", function()
            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              upstream_keepalive = 0,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("# This is the Kong 1.2 default template", contents,
                           nil, true)
            assert.not_matches("keepalive %d+;", contents)

            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              nginx_http_upstream_keepalive = "120", -- not used by template
              upstream_keepalive = 0,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("# This is the Kong 1.2 default template", contents,
                           nil, true)
            assert.not_matches("keepalive %d+;", contents)
          end)

          it("'upstream_keepalive' also sets keepalive if specified", function()
            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              nginx_http_upstream_keepalive = "NONE", -- not used by template
              upstream_keepalive = 60,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("# This is the Kong 1.2 default template", contents,
                           nil, true)
            assert.matches("keepalive 60;", contents, nil, true)

            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              nginx_http_upstream_keepalive = "120", -- not used by template
              upstream_keepalive = 60,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("# This is the Kong 1.2 default template", contents,
                           nil, true)
            assert.matches("keepalive 60;", contents, nil, true)
          end)
        end)

        describe("latest Nginx template", function()
          local templ_fixture = "spec/fixtures/custom_nginx.template"

          it("'upstream_keepalive = 0' has highest precedence", function()
            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              upstream_keepalive = 0,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.not_matches("keepalive %d+;", contents)

            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              nginx_http_upstream_keepalive = "120",
              upstream_keepalive = 0,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.not_matches("keepalive %d+;", contents)
          end)

          it("'nginx_http_upstream_keepalive' has second highest precedence", function()
            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              nginx_http_upstream_keepalive = "120",
              upstream_keepalive = 60,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("keepalive 120;", contents, nil, true)

            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              nginx_http_upstream_keepalive = "60",
              upstream_keepalive = 120,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("keepalive 60;", contents, nil, true)
          end)

          it("'upstream_keepalive' has lowest precedence", function()
            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              upstream_keepalive = 120,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("keepalive 120;", contents, nil, true)

            local conf = assert(conf_loader(helpers.test_conf_path, {
              prefix = tmp_config.prefix,
              upstream_keepalive = 120,
            }))

            assert(prefix_handler.prepare_prefix(conf, templ_fixture))
            assert.truthy(exists(conf.nginx_conf))

            local contents = helpers.file.read(tmp_config.nginx_conf)
            assert.matches("keepalive 120;", contents, nil, true)
          end)

        end)
      end)
    end)
  end)
end)
