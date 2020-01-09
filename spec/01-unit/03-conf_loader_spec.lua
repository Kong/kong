local conf_loader = require "kong.conf_loader"
local helpers = require "spec.helpers"
local tablex = require "pl.tablex"


local function search_directive(tbl, directive_name, directive_value)
  for _, directive in pairs(tbl) do
    if directive.name == directive_name
       and directive.value == directive_value then
      return true
    end
  end

  return false
end


describe("Configuration loader", function()
  it("loads the defaults", function()
    local conf = assert(conf_loader())
    assert.is_string(conf.lua_package_path)
    assert.is_nil(conf.nginx_main_user)
    assert.equal("auto", conf.nginx_main_worker_processes)
    assert.same({"127.0.0.1:8001 reuseport backlog=16384", "127.0.0.1:8444 http2 ssl reuseport backlog=16384"}, conf.admin_listen)
    assert.same({"0.0.0.0:8000 reuseport backlog=16384", "0.0.0.0:8443 http2 ssl reuseport backlog=16384"}, conf.proxy_listen)
    assert.is_nil(conf.ssl_cert) -- check placeholder value
    assert.is_nil(conf.ssl_cert_key)
    assert.is_nil(conf.admin_ssl_cert)
    assert.is_nil(conf.admin_ssl_cert_key)
    assert.is_nil(getmetatable(conf))
  end)
  it("loads a given file, with higher precedence", function()
    local conf = assert(conf_loader(helpers.test_conf_path))
    -- defaults
    assert.equal("on", conf.nginx_main_daemon)
    -- overrides
    assert.is_nil(conf.nginx_main_user)
    assert.equal("1", conf.nginx_main_worker_processes)
    assert.same({"127.0.0.1:9001"}, conf.admin_listen)
    assert.same({"0.0.0.0:9000", "0.0.0.0:9443 http2 ssl",
                 "0.0.0.0:9002 http2"}, conf.proxy_listen)
    assert.is_nil(getmetatable(conf))
  end)
  it("preserves default properties if not in given file", function()
    local conf = assert(conf_loader(helpers.test_conf_path))
    assert.is_string(conf.lua_package_path) -- still there
  end)
  it("accepts custom params, with highest precedence", function()
    local conf = assert(conf_loader(helpers.test_conf_path, {
      admin_listen = "127.0.0.1:9001",
      nginx_main_worker_processes = "auto"
    }))
    -- defaults
    assert.equal("on", conf.nginx_main_daemon)
    -- overrides
    assert.is_nil(conf.nginx_main_user)
    assert.equal("auto", conf.nginx_main_worker_processes)
    assert.same({"127.0.0.1:9001"}, conf.admin_listen)
    assert.same({"0.0.0.0:9000", "0.0.0.0:9443 http2 ssl",
                 "0.0.0.0:9002 http2"}, conf.proxy_listen)
    assert.is_nil(getmetatable(conf))
  end)
  it("strips extraneous properties (not in defaults)", function()
    local conf = assert(conf_loader(nil, {
      stub_property = "leave me alone"
    }))
    assert.is_nil(conf.stub_property)
  end)
  it("returns a plugins table", function()
    local constants = require "kong.constants"
    local conf = assert(conf_loader())
    assert.same(constants.BUNDLED_PLUGINS, conf.loaded_plugins)
  end)
  it("loads custom plugins", function()
    local conf = assert(conf_loader(nil, {
      plugins = "hello-world,my-plugin"
    }))
    assert.True(conf.loaded_plugins["hello-world"])
    assert.True(conf.loaded_plugins["my-plugin"])
  end)
  it("merges plugins and custom plugins", function()
    local conf = assert(conf_loader(nil, {
      plugins = "foo, bar",
    }))
    assert.is_not_nil(conf.loaded_plugins)
    assert.same(2, tablex.size(conf.loaded_plugins))
    assert.True(conf.loaded_plugins["foo"])
    assert.True(conf.loaded_plugins["bar"])
  end)
  it("loads custom plugins surrounded by spaces", function()
    local conf = assert(conf_loader(nil, {
      plugins = " hello-world ,   another-one  "
    }))
    assert.True(conf.loaded_plugins["hello-world"])
    assert.True(conf.loaded_plugins["another-one"])
  end)
  it("extracts flags, ports and listen ips from proxy_listen/admin_listen", function()
    local conf = assert(conf_loader())
    assert.equal("127.0.0.1", conf.admin_listeners[1].ip)
    assert.equal(8001, conf.admin_listeners[1].port)
    assert.equal(false, conf.admin_listeners[1].ssl)
    assert.equal(false, conf.admin_listeners[1].http2)
    assert.equal("127.0.0.1:8001 reuseport backlog=16384", conf.admin_listeners[1].listener)

    assert.equal("127.0.0.1", conf.admin_listeners[2].ip)
    assert.equal(8444, conf.admin_listeners[2].port)
    assert.equal(true, conf.admin_listeners[2].ssl)
    assert.equal(true, conf.admin_listeners[2].http2)
    assert.equal("127.0.0.1:8444 ssl http2 reuseport backlog=16384", conf.admin_listeners[2].listener)

    assert.equal("0.0.0.0", conf.proxy_listeners[1].ip)
    assert.equal(8000, conf.proxy_listeners[1].port)
    assert.equal(false, conf.proxy_listeners[1].ssl)
    assert.equal(false, conf.proxy_listeners[1].http2)
    assert.equal("0.0.0.0:8000 reuseport backlog=16384", conf.proxy_listeners[1].listener)

    assert.equal("0.0.0.0", conf.proxy_listeners[2].ip)
    assert.equal(8443, conf.proxy_listeners[2].port)
    assert.equal(true, conf.proxy_listeners[2].ssl)
    assert.equal(true, conf.proxy_listeners[2].http2)
    assert.equal("0.0.0.0:8443 ssl http2 reuseport backlog=16384", conf.proxy_listeners[2].listener)
  end)
  it("parses IPv6 from proxy_listen/admin_listen", function()
    local conf = assert(conf_loader(nil, {
      proxy_listen = "[::]:8000, [::]:8443 ssl",
      admin_listen = "[::1]:8001, [::1]:8444 ssl",
    }))
    assert.equal("[0000:0000:0000:0000:0000:0000:0000:0001]", conf.admin_listeners[1].ip)
    assert.equal(8001, conf.admin_listeners[1].port)
    assert.equal(false, conf.admin_listeners[1].ssl)
    assert.equal(false, conf.admin_listeners[1].http2)
    assert.equal("[0000:0000:0000:0000:0000:0000:0000:0001]:8001", conf.admin_listeners[1].listener)

    assert.equal("[0000:0000:0000:0000:0000:0000:0000:0001]", conf.admin_listeners[2].ip)
    assert.equal(8444, conf.admin_listeners[2].port)
    assert.equal(true, conf.admin_listeners[2].ssl)
    assert.equal(false, conf.admin_listeners[2].http2)
    assert.equal("[0000:0000:0000:0000:0000:0000:0000:0001]:8444 ssl", conf.admin_listeners[2].listener)

    assert.equal("[0000:0000:0000:0000:0000:0000:0000:0000]", conf.proxy_listeners[1].ip)
    assert.equal(8000, conf.proxy_listeners[1].port)
    assert.equal(false, conf.proxy_listeners[1].ssl)
    assert.equal(false, conf.proxy_listeners[1].http2)
    assert.equal("[0000:0000:0000:0000:0000:0000:0000:0000]:8000", conf.proxy_listeners[1].listener)

    assert.equal("[0000:0000:0000:0000:0000:0000:0000:0000]", conf.proxy_listeners[2].ip)
    assert.equal(8443, conf.proxy_listeners[2].port)
    assert.equal(true, conf.proxy_listeners[2].ssl)
    assert.equal(false, conf.proxy_listeners[2].http2)
    assert.equal("[0000:0000:0000:0000:0000:0000:0000:0000]:8443 ssl", conf.proxy_listeners[2].listener)
  end)
  it("extracts ssl flags properly when hostnames contain them", function()
    local conf
    conf = assert(conf_loader(nil, {
      proxy_listen = "ssl.myname.com:8000",
      admin_listen = "ssl.myname.com:8001",
    }))
    assert.equal("ssl.myname.com", conf.proxy_listeners[1].ip)
    assert.equal(false, conf.proxy_listeners[1].ssl)
    assert.equal("ssl.myname.com", conf.admin_listeners[1].ip)
    assert.equal(false, conf.admin_listeners[1].ssl)

    conf = assert(conf_loader(nil, {
      proxy_listen = "ssl_myname.com:8000 ssl",
      admin_listen = "ssl_myname.com:8001 ssl",
    }))
    assert.equal("ssl_myname.com", conf.proxy_listeners[1].ip)
    assert.equal(true, conf.proxy_listeners[1].ssl)
    assert.equal("ssl_myname.com", conf.admin_listeners[1].ip)
    assert.equal(true, conf.admin_listeners[1].ssl)
  end)
  it("extracts 'off' from proxy_listen/admin_listen", function()
    local conf
    conf = assert(conf_loader(nil, {
      proxy_listen = "off",
      admin_listen = "off",
    }))
    assert.same({}, conf.proxy_listeners)
    assert.same({}, conf.admin_listeners)
    -- off with multiple entries
    conf = assert(conf_loader(nil, {
      proxy_listen = "off, 0.0.0.0:9000",
      admin_listen = "off, 127.0.0.1:9001",
    }))
    assert.same({}, conf.proxy_listeners)
    assert.same({}, conf.admin_listeners)
    -- not off with names containing 'off'
    conf = assert(conf_loader(nil, {
      proxy_listen = "offshore.com:9000",
      admin_listen = "offshore.com:9001",
    }))
    assert.same("offshore.com", conf.proxy_listeners[1].ip)
    assert.same("offshore.com", conf.admin_listeners[1].ip)
  end)
  it("attaches prefix paths", function()
    local conf = assert(conf_loader())
    assert.equal("/usr/local/kong/pids/nginx.pid", conf.nginx_pid)
    assert.equal("/usr/local/kong/logs/error.log", conf.nginx_err_logs)
    assert.equal("/usr/local/kong/logs/access.log", conf.nginx_acc_logs)
    assert.equal("/usr/local/kong/logs/admin_access.log", conf.admin_acc_logs)
    assert.equal("/usr/local/kong/nginx.conf", conf.nginx_conf)
    assert.equal("/usr/local/kong/nginx-kong.conf", conf.nginx_kong_conf)
    assert.equal("/usr/local/kong/.kong_env", conf.kong_env)
    -- ssl default paths
    assert.equal("/usr/local/kong/ssl/kong-default.crt", conf.ssl_cert_default)
    assert.equal("/usr/local/kong/ssl/kong-default.key", conf.ssl_cert_key_default)
    assert.equal("/usr/local/kong/ssl/admin-kong-default.crt", conf.admin_ssl_cert_default)
    assert.equal("/usr/local/kong/ssl/admin-kong-default.key", conf.admin_ssl_cert_key_default)
  end)
  it("strips comments ending settings", function()
    local _os_getenv = os.getenv
    finally(function()
      os.getenv = _os_getenv -- luacheck: ignore
    end)
    os.getenv = function() end -- luacheck: ignore

    local conf = assert(conf_loader("spec/fixtures/to-strip.conf"))

    assert.equal("cassandra", conf.database)
    assert.equal("debug", conf.log_level)
  end)
  it("overcomes penlight's list_delim option", function()
    local conf = assert(conf_loader("spec/fixtures/to-strip.conf"))
    assert.False(conf.pg_ssl)
    assert.True(conf.loaded_plugins.foobar)
    assert.True(conf.loaded_plugins["hello-world"])
  end)
  it("correctly parses values containing an octothorpe", function()
    local conf = assert(conf_loader("spec/fixtures/to-strip.conf"))
    assert.equal("test#123", conf.pg_password)
  end)
  it("escapes unescaped octothorpes in environment variables", function()
    finally(function()
      helpers.unsetenv("KONG_PG_PASSWORD")
    end)
    helpers.setenv("KONG_PG_PASSWORD", "test#123")
    local conf = assert(conf_loader())
    assert.equal("test#123", conf.pg_password)

    helpers.setenv("KONG_PG_PASSWORD", "test#12#3")
    local conf = assert(conf_loader())
    assert.equal("test#12#3", conf.pg_password)

    helpers.setenv("KONG_PG_PASSWORD", "test##12##3#")
    local conf = assert(conf_loader())
    assert.equal("test##12##3#", conf.pg_password)
  end)
  it("escapes unescaped octothorpes in custom_conf overrides", function()
    local conf = assert(conf_loader(nil, {
      pg_password = "test#123",
    }))
    assert.equal("test#123", conf.pg_password)

    local conf = assert(conf_loader(nil, {
      pg_password = "test#12#3",
    }))
    assert.equal("test#12#3", conf.pg_password)

    local conf = assert(conf_loader(nil, {
      pg_password = "test##12##3#",
    }))
    assert.equal("test##12##3#", conf.pg_password)
  end)
  it("does not modify existing escaped octothorpes in environment variables", function()
    finally(function()
      helpers.unsetenv("KONG_PG_PASSWORD")
    end)
    helpers.setenv("KONG_PG_PASSWORD", [[test\#123]])
    local conf = assert(conf_loader())
    assert.equal("test#123", conf.pg_password)

    helpers.setenv("KONG_PG_PASSWORD", [[test\#\#12\#\#3\#]])
    local conf = assert(conf_loader())
    assert.equal("test##12##3#", conf.pg_password)
  end)
  it("does not modify existing escaped octothorpes in custom_conf overrides", function()
    local conf = assert(conf_loader(nil, {
      pg_password = [[test\#123]],
    }))
    assert.equal("test#123", conf.pg_password)

    local conf = assert(conf_loader(nil, {
      pg_password = [[test\#\#12\#\#3\#]],
    }))
    assert.equal("test##12##3#", conf.pg_password)
  end)

  describe("dynamic directives", function()
    it("loads flexible prefix based configs from a file", function()
      local conf = assert(conf_loader("spec/fixtures/nginx-directives.conf", {
        plugins = "off",
      }))
      assert.True(search_directive(conf.nginx_http_directives,
                                   "variables_hash_bucket_size", "128"))
      assert.True(search_directive(conf.nginx_stream_directives,
                                   "variables_hash_bucket_size", "128"))

      assert.True(search_directive(conf.nginx_http_directives,
                                   "lua_shared_dict", "custom_cache 5m"))
      assert.True(search_directive(conf.nginx_stream_directives,
                                   "lua_shared_dict", "custom_cache 5m"))

      assert.True(search_directive(conf.nginx_proxy_directives,
                                   "proxy_bind", "127.0.0.1"))
      assert.True(search_directive(conf.nginx_sproxy_directives,
                                   "proxy_bind", "127.0.0.1"))

      assert.True(search_directive(conf.nginx_admin_directives,
                                   "server_tokens", "off"))
    end)

    it("quotes numeric flexible prefix based configs", function()
      local conf, err = conf_loader(nil, {
        ["nginx_http_max_pending_timers"] = 4096,
      })
      assert.is_nil(err)

      assert.True(search_directive(conf.nginx_http_directives,
                  "max_pending_timers", "4096"))
    end)

    it("accepts flexible config values with precedence", function()
      local conf = assert(conf_loader("spec/fixtures/nginx-directives.conf", {
        ["nginx_http_variables_hash_bucket_size"] = "256",
        ["nginx_stream_variables_hash_bucket_size"] = "256",
        ["nginx_http_lua_shared_dict"] = "custom_cache 2m",
        ["nginx_stream_lua_shared_dict"] = "custom_cache 2m",
        ["nginx_proxy_proxy_bind"] = "127.0.0.2",
        ["nginx_sproxy_proxy_bind"] = "127.0.0.2",
        ["nginx_admin_server_tokens"] = "build",
        plugins = "off",
      }))

      assert.True(search_directive(conf.nginx_http_directives,
                                   "variables_hash_bucket_size", "256"))
      assert.True(search_directive(conf.nginx_stream_directives,
                                   "variables_hash_bucket_size", "256"))

      assert.True(search_directive(conf.nginx_http_directives,
                                   "lua_shared_dict", "custom_cache 2m"))
      assert.True(search_directive(conf.nginx_stream_directives,
                                   "lua_shared_dict", "custom_cache 2m"))

      assert.True(search_directive(conf.nginx_proxy_directives,
                                   "proxy_bind", "127.0.0.2"))
      assert.True(search_directive(conf.nginx_sproxy_directives,
                                   "proxy_bind", "127.0.0.2"))

      assert.True(search_directive(conf.nginx_admin_directives,
                                   "server_tokens", "build"))
      assert.True(search_directive(conf.nginx_status_directives,
                                   "client_body_buffer_size", "8k"))
    end)
  end)

  describe("prometheus_metrics shm", function()
    it("is injected if not provided via nginx_http_* directives", function()
      local conf = assert(conf_loader())
      assert.True(search_directive(conf.nginx_http_directives,
                  "lua_shared_dict", "prometheus_metrics 5m"))
    end)
    it("size is not modified if provided via nginx_http_* directives", function()
      local conf = assert(conf_loader(nil, {
        plugins = "bundled",
        nginx_http_lua_shared_dict = "prometheus_metrics 2m",
      }))
      assert.True(search_directive(conf.nginx_http_directives,
                  "lua_shared_dict", "prometheus_metrics 2m"))
    end)
    it("is injected in addition to any shm provided via nginx_http_* directive", function()
      local conf = assert(conf_loader(nil, {
        plugins = "bundled",
        nginx_http_lua_shared_dict = "custom_cache 2m",
      }))
      assert.True(search_directive(conf.nginx_http_directives,
                  "lua_shared_dict", "custom_cache 2m"))
      assert.True(search_directive(conf.nginx_http_directives,
                  "lua_shared_dict", "prometheus_metrics 5m"))
    end)
    it("is not injected if prometheus plugin is disabled", function()
      local conf = assert(conf_loader(nil, {
        plugins = "off",
      }))
      assert.is_nil(conf.nginx_http_directives["lua_shared_dict"])
    end)
  end)

  describe("nginx_main_user", function()
    it("is nil by default", function()
      local conf = assert(conf_loader(helpers.test_conf_path))
      assert.is_nil(conf.nginx_main_user)
    end)
    it("is nil when 'nobody'", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        nginx_main_user = "nobody"
      }))
      assert.is_nil(conf.nginx_main_user)
    end)
    it("is nil when 'nobody nobody'", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        nginx_main_user = "nobody nobody"
      }))
      assert.is_nil(conf.nginx_main_user)
    end)
    it("is 'www_data www_data' when 'www_data www_data'", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        nginx_main_user = "www_data www_data"
      }))
      assert.equal("www_data www_data", conf.nginx_main_user)
    end)
  end)

  describe("nginx_user", function()
    it("is nil when 'nobody'", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        nginx_user = "nobody"
      }))
      assert.is_nil(conf.nginx_user)
    end)
    it("is nil when 'nobody nobody'", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        nginx_user = "nobody nobody"
      }))
      assert.is_nil(conf.nginx_user)
    end)
    it("is 'www_data www_data' when 'www_data www_data'", function()
      local conf = assert(conf_loader(helpers.test_conf_path, {
        nginx_user = "www_data www_data"
      }))
      assert.equal("www_data www_data", conf.nginx_user)
    end)
  end)

  describe("inferences", function()
    it("infer booleans (on/off/true/false strings)", function()
      local conf = assert(conf_loader())
      assert.equal("on", conf.nginx_main_daemon)
      assert.equal(30, conf.lua_socket_pool_size)
      assert.True(conf.anonymous_reports)
      assert.False(conf.cassandra_ssl)
      assert.False(conf.cassandra_ssl_verify)
      assert.False(conf.pg_ssl)
      assert.False(conf.pg_ssl_verify)

      conf = assert(conf_loader(nil, {
        cassandra_ssl = true,
        pg_ssl = true
      }))
      assert.True(conf.cassandra_ssl)
      assert.True(conf.pg_ssl)

      conf = assert(conf_loader(nil, {
        cassandra_ssl = "on",
        pg_ssl = "on"
      }))
      assert.True(conf.cassandra_ssl)
      assert.True(conf.pg_ssl)

      conf = assert(conf_loader(nil, {
        cassandra_ssl = "true",
        pg_ssl = "true"
      }))
      assert.True(conf.cassandra_ssl)
      assert.True(conf.pg_ssl)
    end)
    it("infer arrays (comma-separated strings)", function()
      local conf = assert(conf_loader())
      assert.same({"127.0.0.1"}, conf.cassandra_contact_points)
      assert.same({"dc1:2", "dc2:3"}, conf.cassandra_data_centers)
      assert.is_nil(getmetatable(conf.cassandra_contact_points))
      assert.is_nil(getmetatable(conf.cassandra_data_centers))
    end)
    it("trims array values", function()
      local conf = assert(conf_loader("spec/fixtures/to-strip.conf"))
      assert.same({"dc1:2", "dc2:3", "dc3:4"}, conf.cassandra_data_centers)
    end)
    it("infer ngx_boolean", function()
      local conf = assert(conf_loader(nil, {
        nginx_main_daemon = true
      }))
      assert.equal("on", conf.nginx_main_daemon)

      conf = assert(conf_loader(nil, {
        nginx_main_daemon = false
      }))
      assert.equal("off", conf.nginx_main_daemon)

      conf = assert(conf_loader(nil, {
        nginx_main_daemon = "off"
      }))
      assert.equal("off", conf.nginx_main_daemon)
    end)
  end)

  describe("validations", function()
    it("enforces properties types", function()
      local conf, err = conf_loader(nil, {
        lua_package_path = 123
      })
      assert.equal("lua_package_path is not a string: '123'", err)
      assert.is_nil(conf)
    end)
    it("enforces enums", function()
      local conf, err = conf_loader(nil, {
        database = "mysql"
      })
      assert.equal("database has an invalid value: 'mysql' (postgres, cassandra, off)", err)
      assert.is_nil(conf)

      local conf, err = conf_loader(nil, {
        router_consistency = "magical"
      })
      assert.equal("router_consistency has an invalid value: 'magical' (strict, eventual)", err)
      assert.is_nil(conf)

      conf, err = conf_loader(nil, {
        cassandra_consistency = "FOUR"
      })
      assert.equal("cassandra_consistency has an invalid value: 'FOUR'"
                 .. " (ALL, EACH_QUORUM, QUORUM, LOCAL_QUORUM, ONE, TWO,"
                 .. " THREE, LOCAL_ONE)", err)
      assert.is_nil(conf)

    end)
    it("enforces listen addresses format", function()
      local conf, err = conf_loader(nil, {
        admin_listen = "127.0.0.1"
      })
      assert.is_nil(conf)
      assert.equal("admin_listen must be of form: [off] | <ip>:<port> [ssl] [http2] [proxy_protocol] [deferred] [bind] [reuseport] [backlog=%d+], [... next entry ...]", err)

      conf, err = conf_loader(nil, {
        proxy_listen = "127.0.0.1"
      })
      assert.is_nil(conf)
      assert.equal("proxy_listen must be of form: [off] | <ip>:<port> [ssl] [http2] [proxy_protocol] [deferred] [bind] [reuseport] [backlog=%d+], [... next entry ...]", err)
    end)
    it("rejects empty string in listen addresses", function()
      local conf, err = conf_loader(nil, {
        admin_listen = ""
      })
      assert.is_nil(conf)
      assert.equal("admin_listen must be of form: [off] | <ip>:<port> [ssl] [http2] [proxy_protocol] [deferred] [bind] [reuseport] [backlog=%d+], [... next entry ...]", err)

      conf, err = conf_loader(nil, {
        proxy_listen = ""
      })
      assert.is_nil(conf)
      assert.equal("proxy_listen must be of form: [off] | <ip>:<port> [ssl] [http2] [proxy_protocol] [deferred] [bind] [reuseport] [backlog=%d+], [... next entry ...]", err)
    end)
    it("errors when dns_resolver is not a list in ipv4/6[:port] format", function()
      local conf, err = conf_loader(nil, {
        dns_resolver = "1.2.3.4:53;4.3.2.1" -- ; as separator
      })
      assert.equal("dns_resolver must be a comma separated list in the form of IPv4/6 or IPv4/6:port, got '1.2.3.4:53;4.3.2.1'", err)
      assert.is_nil(conf)

      conf, err = conf_loader(nil, {
        dns_resolver = "8.8.8.8:53"
      })
      assert.is_nil(err)
      assert.is_table(conf)

      conf, err = conf_loader(nil, {
        dns_resolver = "[::1]:53"
      })
      assert.is_nil(err)
      assert.is_table(conf)

      conf, err = conf_loader(nil, {
        dns_resolver = "8.8.8.8,1.2.3.4:53,::1,[::1]:53"
      })
      assert.is_nil(err)
      assert.is_table(conf)
    end)
    it("errors when the hosts file does not exist", function()
      local tmpfile = "/a_file_that_does_not_exist"
      local conf, err = conf_loader(nil, {
        dns_hostsfile = tmpfile,
      })
      assert.equal([[dns_hostsfile: file does not exist]], err)
      assert.is_nil(conf)
    end)
    it("accepts an existing hosts file", function()
      local tmpfile = require("pl.path").tmpname()  -- this creates the file!
      finally(function() os.remove(tmpfile) end)
      local conf, err = conf_loader(nil, {
        dns_hostsfile = tmpfile,
      })
      assert.is_nil(err)
      assert.equal(tmpfile, conf.dns_hostsfile)
    end)
    it("errors on bad entries in the order list", function()
      local conf, err = conf_loader(nil, {
        dns_order = "A,CXAME,SRV",
      })
      assert.is_nil(conf)
      assert.equal([[dns_order: invalid entry 'CXAME']], err)
    end)
    it("errors on bad entries in headers", function()
      local conf, err = conf_loader(nil, {
        headers = "server_tokens,Foo-Bar",
      })
      assert.is_nil(conf)
      assert.equal([[headers: invalid entry 'Foo-Bar']], err)
    end)
    it("errors when hosts have a bad format in cassandra_contact_points", function()
      local conf, err = conf_loader(nil, {
          database                 = "cassandra",
          cassandra_contact_points = [[some/really\bad/host\name,addr2]]
      })
      assert.equal([[bad cassandra contact point 'some/really\bad/host\name': invalid hostname: some/really\bad/host\name]], err)
      assert.is_nil(conf)
    end)
    it("errors cassandra_refresh_frequency is < 0", function()
      local conf, err = conf_loader(nil, {
          database                    = "cassandra",
          cassandra_refresh_frequency = -1,
      })
      assert.equal("cassandra_refresh_frequency must be 0 or greater", err)
      assert.is_nil(conf)
    end)
    it("errors when specifying a port in cassandra_contact_points", function()
      local conf, err = conf_loader(nil, {
          database                 = "cassandra",
          cassandra_contact_points = "addr1:9042,addr2"
      })
      assert.equal("bad cassandra contact point 'addr1:9042': port must be specified in cassandra_port", err)
      assert.is_nil(conf)
    end)
    describe("SSL", function()
      describe("proxy", function()
        it("does not check SSL cert and key if SSL is off", function()
          local conf, err = conf_loader(nil, {
            proxy_listen = "127.0.0.1:123",
            ssl_cert = "/path/cert.pem"
          })
          assert.is_nil(err)
          assert.is_table(conf)
          -- specific case with 'ssl' in the name
          local conf, err = conf_loader(nil, {
            proxy_listen = "ssl:23",
            proxy_ssl_cert = "/path/cert.pem"
          })
          assert.is_nil(err)
          assert.is_table(conf)
        end)
        it("requires both proxy SSL cert and key", function()
          local conf, err = conf_loader(nil, {
            ssl_cert = "/path/cert.pem"
          })
          assert.equal("ssl_cert_key must be specified", err)
          assert.is_nil(conf)

          conf, err = conf_loader(nil, {
            ssl_cert_key = "/path/key.pem"
          })
          assert.equal("ssl_cert must be specified", err)
          assert.is_nil(conf)

          conf, err = conf_loader(nil, {
            ssl_cert = "spec/fixtures/kong_spec.crt",
            ssl_cert_key = "spec/fixtures/kong_spec.key"
          })
          assert.is_nil(err)
          assert.is_table(conf)
        end)
        it("requires SSL cert and key to exist", function()
          local conf, _, errors = conf_loader(nil, {
            ssl_cert = "/path/cert.pem",
            ssl_cert_key = "/path/cert_key.pem"
          })
          assert.equal(2, #errors)
          assert.contains("ssl_cert: no such file at /path/cert.pem", errors)
          assert.contains("ssl_cert_key: no such file at /path/cert_key.pem", errors)
          assert.is_nil(conf)

          conf, _, errors = conf_loader(nil, {
            ssl_cert = "spec/fixtures/kong_spec.crt",
            ssl_cert_key = "/path/cert_key.pem"
          })
          assert.equal(1, #errors)
          assert.contains("ssl_cert_key: no such file at /path/cert_key.pem", errors)
          assert.is_nil(conf)
        end)
        it("requires trusted CA cert file to exist", function()
          local conf, _, errors = conf_loader(nil, {
            lua_ssl_trusted_certificate = "/path/cert.pem",
          })
          assert.equal(1, #errors)
          assert.contains("lua_ssl_trusted_certificate: no such file at /path/cert.pem", errors)
          assert.is_nil(conf)
        end)
        it("resolves SSL cert/key to absolute path", function()
          local conf, err = conf_loader(nil, {
            ssl_cert = "spec/fixtures/kong_spec.crt",
            ssl_cert_key = "spec/fixtures/kong_spec.key"
          })
          assert.is_nil(err)
          assert.is_table(conf)
          assert.True(helpers.path.isabs(conf.ssl_cert))
          assert.True(helpers.path.isabs(conf.ssl_cert_key))
        end)
        it("defines ssl_ciphers by default", function()
          local conf, err = conf_loader(nil, {})
          assert.is_nil(err)
          assert.equal("ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384", conf.ssl_ciphers)
        end)
        it("explicitly defines ssl_ciphers", function()
          local conf, err = conf_loader(nil, {
            ssl_cipher_suite = "old"
          })
          assert.is_nil(err)
          -- looks kinda like a cipher suite
          assert.matches(":", conf.ssl_ciphers, nil, true)
        end)
        it("errors on invalid ssl_cipher_suite", function()
          local conf, _, errors = conf_loader(nil, {
            ssl_cipher_suite = "foo"
          })
          assert.is_nil(conf)
          assert.equal(1, #errors)
          assert.matches("Undefined cipher suite foo", errors[1], nil, true)
        end)
        it("overrides ssl_ciphers when ssl_cipher_suite is custom", function()
          local conf, err = conf_loader(nil, {
            ssl_cipher_suite = "custom",
            ssl_ciphers      = "foo:bar",
          })
          assert.is_nil(err)
          assert.equals("foo:bar", conf.ssl_ciphers)
        end)
        it("doesn't override ssl_ciphers when undefined", function()
          local conf, err = conf_loader(nil, {
            ssl_cipher_suite = "custom",
          })
          assert.is_nil(err)
          assert.same(nil, conf.ssl_ciphers)
        end)
      end)
      describe("client", function()
        it("requires both proxy SSL cert and key", function()
          local conf, err = conf_loader(nil, {
            client_ssl = true,
            client_ssl_cert = "/path/cert.pem"
          })
          assert.equal("client_ssl_cert_key must be specified", err)
          assert.is_nil(conf)

          conf, err = conf_loader(nil, {
            client_ssl = true,
            client_ssl_cert_key = "/path/key.pem"
          })
          assert.equal("client_ssl_cert must be specified", err)
          assert.is_nil(conf)

          conf, err = conf_loader(nil, {
            client_ssl = true,
            client_ssl_cert = "spec/fixtures/kong_spec.crt",
            client_ssl_cert_key = "spec/fixtures/kong_spec.key"
          })
          assert.is_nil(err)
          assert.is_table(conf)
        end)
        it("requires SSL cert and key to exist", function()
          local conf, _, errors = conf_loader(nil, {
            client_ssl = true,
            client_ssl_cert = "/path/cert.pem",
            client_ssl_cert_key = "/path/cert_key.pem"
          })
          assert.equal(2, #errors)
          assert.contains("client_ssl_cert: no such file at /path/cert.pem", errors)
          assert.contains("client_ssl_cert_key: no such file at /path/cert_key.pem", errors)
          assert.is_nil(conf)

          conf, _, errors = conf_loader(nil, {
            client_ssl = true,
            client_ssl_cert = "spec/fixtures/kong_spec.crt",
            client_ssl_cert_key = "/path/cert_key.pem"
          })
          assert.equal(1, #errors)
          assert.contains("client_ssl_cert_key: no such file at /path/cert_key.pem", errors)
          assert.is_nil(conf)
        end)
        it("resolves SSL cert/key to absolute path", function()
          local conf, err = conf_loader(nil, {
            client_ssl = true,
            client_ssl_cert = "spec/fixtures/kong_spec.crt",
            client_ssl_cert_key = "spec/fixtures/kong_spec.key"
          })
          assert.is_nil(err)
          assert.is_table(conf)
          assert.True(helpers.path.isabs(conf.client_ssl_cert))
          assert.True(helpers.path.isabs(conf.client_ssl_cert_key))
        end)
      end)
      describe("admin", function()
        it("does not check SSL cert and key if SSL is off", function()
          local conf, err = conf_loader(nil, {
            admin_listen = "127.0.0.1:123",
            admin_ssl_cert = "/path/cert.pem"
          })
          assert.is_nil(err)
          assert.is_table(conf)
          -- specific case with 'ssl' in the name
          local conf, err = conf_loader(nil, {
            admin_listen = "ssl:23",
            admin_ssl_cert = "/path/cert.pem"
          })
          assert.is_nil(err)
          assert.is_table(conf)
        end)
        it("requires both admin SSL cert and key", function()
          local conf, err = conf_loader(nil, {
            admin_ssl_cert = "/path/cert.pem"
          })
          assert.equal("admin_ssl_cert_key must be specified", err)
          assert.is_nil(conf)

          conf, err = conf_loader(nil, {
            admin_ssl_cert_key = "/path/key.pem"
          })
          assert.equal("admin_ssl_cert must be specified", err)
          assert.is_nil(conf)

          conf, err = conf_loader(nil, {
            admin_ssl_cert = "spec/fixtures/kong_spec.crt",
            admin_ssl_cert_key = "spec/fixtures/kong_spec.key"
          })
          assert.is_nil(err)
          assert.is_table(conf)
        end)
        it("requires SSL cert and key to exist", function()
          local conf, _, errors = conf_loader(nil, {
            admin_ssl_cert = "/path/cert.pem",
            admin_ssl_cert_key = "/path/cert_key.pem"
          })
          assert.equal(2, #errors)
          assert.contains("admin_ssl_cert: no such file at /path/cert.pem", errors)
          assert.contains("admin_ssl_cert_key: no such file at /path/cert_key.pem", errors)
          assert.is_nil(conf)

          conf, _, errors = conf_loader(nil, {
            admin_ssl_cert = "spec/fixtures/kong_spec.crt",
            admin_ssl_cert_key = "/path/cert_key.pem"
          })
          assert.equal(1, #errors)
          assert.contains("admin_ssl_cert_key: no such file at /path/cert_key.pem", errors)
          assert.is_nil(conf)
        end)
        it("resolves SSL cert/key to absolute path", function()
          local conf, err = conf_loader(nil, {
            admin_ssl_cert = "spec/fixtures/kong_spec.crt",
            admin_ssl_cert_key = "spec/fixtures/kong_spec.key"
          })
          assert.is_nil(err)
          assert.is_table(conf)
          assert.True(helpers.path.isabs(conf.admin_ssl_cert))
          assert.True(helpers.path.isabs(conf.admin_ssl_cert_key))
        end)
      end)
    end)
    it("honors path if provided even if a default file exists", function()
      conf_loader.add_default_path("spec/fixtures/to-strip.conf")

      local _os_getenv = os.getenv
      finally(function()
        os.getenv = _os_getenv -- luacheck: ignore
        package.loaded["kong.conf_loader"] = nil
        conf_loader = require "kong.conf_loader"
      end)
      os.getenv = function() end -- luacheck: ignore

      local conf = assert(conf_loader(helpers.test_conf_path))
      assert.equal("postgres", conf.database)
    end)
    it("requires cassandra_local_datacenter if DCAware LB policy is in use", function()
      for _, policy in ipairs({ "DCAwareRoundRobin", "RequestDCAwareRoundRobin" }) do
        local conf, err = conf_loader(nil, {
          database            = "cassandra",
          cassandra_lb_policy = policy,
        })
        assert.is_nil(conf)
        assert.equal("must specify 'cassandra_local_datacenter' when " ..
                     policy .. " policy is in use", err)
      end
    end)
    it("honors path if provided even if a default file exists", function()
      conf_loader.add_default_path("spec/fixtures/to-strip.conf")

      local _os_getenv = os.getenv
      finally(function()
        os.getenv = _os_getenv -- luacheck: ignore
        package.loaded["kong.conf_loader"] = nil
        conf_loader = require "kong.conf_loader"
      end)
      os.getenv = function() end -- luacheck: ignore

      local conf = assert(conf_loader(helpers.test_conf_path))
      assert.equal("postgres", conf.database)
    end)
  end)

  describe("pg_semaphore options", function()
    it("rejects a pg_max_concurrent_queries with a negative number", function()
      local conf, err = conf_loader(nil, {
        pg_max_concurrent_queries = -1,
      })
      assert.is_nil(conf)
      assert.equal("pg_max_concurrent_queries must be greater than 0", err)
    end)

    it("rejects a pg_max_concurrent_queries with a decimal", function()
      local conf, err = conf_loader(nil, {
        pg_max_concurrent_queries = 0.1,
      })
      assert.is_nil(conf)
      assert.equal("pg_max_concurrent_queries must be an integer greater than 0", err)
    end)

    it("rejects a pg_semaphore_timeout with a negative number", function()
      local conf, err = conf_loader(nil, {
        pg_semaphore_timeout = -1,
      })
      assert.is_nil(conf)
      assert.equal("pg_semaphore_timeout must be greater than 0", err)
    end)

    it("rejects a pg_semaphore_timeout with a decimal", function()
      local conf, err = conf_loader(nil, {
        pg_semaphore_timeout = 0.1,
      })
      assert.is_nil(conf)
      assert.equal("pg_semaphore_timeout must be an integer greater than 0", err)
    end)
  end)

  describe("router_update_frequency option", function()
    it("is rejected with a zero", function()
      local conf, err = conf_loader(nil, {
        router_update_frequency = 0,
      })
      assert.is_nil(conf)
      assert.equal("router_update_frequency must be greater than 0", err)
    end)
    it("is rejected with a negative number", function()
      local conf, err = conf_loader(nil, {
        router_update_frequency = -1,
      })
      assert.is_nil(conf)
      assert.equal("router_update_frequency must be greater than 0", err)
    end)
    it("accepts decimal numbers", function()
      local conf, err = conf_loader(nil, {
        router_update_frequency = 0.01,
      })
      assert.equal(conf.router_update_frequency, 0.01)
      assert.is_nil(err)
    end)
  end)

  describe("errors", function()
    it("returns inexistent file", function()
      local conf, err = conf_loader "inexistent"
      assert.equal("no file at: inexistent", err)
      assert.is_nil(conf)
    end)
    it("returns all errors in ret value #3", function()
      local conf, _, errors = conf_loader(nil, {
        cassandra_repl_strategy = "foo",
        ssl_cert_key = "spec/fixtures/kong_spec.key"
      })
      assert.equal(2, #errors)
      assert.is_nil(conf)
      assert.contains("cassandra_repl_strategy has", errors, true)
      assert.contains("ssl_cert must be specified", errors)
    end)
  end)

  describe("remove_sensitive()", function()
    it("replaces sensitive settings", function()
      local conf = assert(conf_loader(nil, {
        pg_password = "hide_me",
        cassandra_password = "hide_me",
      }))

      local purged_conf = conf_loader.remove_sensitive(conf)
      assert.not_equal("hide_me", purged_conf.pg_password)
      assert.not_equal("hide_me", purged_conf.cassandra_password)
    end)
    it("does not insert placeholder if no value", function()
      local conf = assert(conf_loader())
      local purged_conf = conf_loader.remove_sensitive(conf)
      assert.is_nil(purged_conf.pg_password)
      assert.is_nil(purged_conf.cassandra_password)
    end)
  end)

  describe("number as string", function()
    it("force the numeric pg_password/cassandra_password to a string", function()
      local conf = assert(conf_loader(nil, {
        pg_password = 123456,
        cassandra_password = 123456
      }))

      assert.equal("123456", conf.pg_password)
      assert.equal("123456", conf.cassandra_password)
    end)
  end)
end)
