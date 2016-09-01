local conf_loader = require "kong.conf_loader"
local helpers = require "spec.helpers"

describe("Configuration loader", function()
  it("loads the defaults", function()
    local conf = assert(conf_loader())
    assert.is_string(conf.lua_package_path)
    assert.equal("auto", conf.nginx_worker_processes)
    assert.equal("0.0.0.0:8001", conf.admin_listen)
    assert.equal("0.0.0.0:8000", conf.proxy_listen)
    assert.equal("0.0.0.0:8443", conf.proxy_listen_ssl)
    assert.is_nil(conf.ssl_cert) -- check placeholder value
    assert.is_nil(conf.ssl_cert_key)
    assert.is_nil(getmetatable(conf))
  end)
  it("loads a given file, with higher precedence", function()
    local conf = assert(conf_loader(helpers.test_conf_path))
    -- defaults
    assert.equal("on", conf.nginx_daemon)
    -- overrides
    assert.equal("1", conf.nginx_worker_processes)
    assert.equal("0.0.0.0:9001", conf.admin_listen)
    assert.equal("0.0.0.0:9000", conf.proxy_listen)
    assert.equal("0.0.0.0:9443", conf.proxy_listen_ssl)
    assert.is_nil(getmetatable(conf))
  end)
  it("preserves default properties if not in given file", function()
    local conf = assert(conf_loader(helpers.test_conf_path))
    assert.is_string(conf.lua_package_path) -- still there
  end)
  it("accepts custom params, with highest precedence", function()
    local conf = assert(conf_loader(helpers.test_conf_path, {
      admin_listen = "127.0.0.1:9001",
      nginx_worker_processes = "auto"
    }))
    -- defaults
    assert.equal("on", conf.nginx_daemon)
    -- overrides
    assert.equal("auto", conf.nginx_worker_processes)
    assert.equal("127.0.0.1:9001", conf.admin_listen)
    assert.equal("0.0.0.0:9000", conf.proxy_listen)
    assert.equal("0.0.0.0:9443", conf.proxy_listen_ssl)
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
    assert.is_nil(conf.custom_plugins)
    assert.same(constants.PLUGINS_AVAILABLE, conf.plugins)
  end)
  it("loads custom plugins", function()
    local conf = assert(conf_loader(nil, {
      custom_plugins = "hello-world,my-plugin"
    }))
    assert.is_nil(conf.custom_plugins)
    assert.True(conf.plugins["hello-world"])
    assert.True(conf.plugins["my-plugin"])
  end)
  it("extracts ports and listen ips from proxy_listen/admin_listen", function()
    local conf = assert(conf_loader())
    assert.equal("0.0.0.0", conf.admin_ip)
    assert.equal(8001, conf.admin_port)
    assert.equal("0.0.0.0", conf.proxy_ip)
    assert.equal(8000, conf.proxy_port)
    assert.equal("0.0.0.0", conf.proxy_ssl_ip)
    assert.equal(8443, conf.proxy_ssl_port)
  end)
  it("attaches prefix paths", function()
    local conf = assert(conf_loader())
    assert.equal("/usr/local/kong/pids/serf.pid", conf.serf_pid)
    assert.equal("/usr/local/kong/logs/serf.log", conf.serf_log)
    assert.equal("/usr/local/kong/serf/serf_event.sh", conf.serf_event)
    assert.equal("/usr/local/kong/serf/serf.id", conf.serf_node_id)
    assert.equal("/usr/local/kong/pids/nginx.pid", conf.nginx_pid)
    assert.equal("/usr/local/kong/logs/error.log", conf.nginx_err_logs)
    assert.equal("/usr/local/kong/logs/access.log", conf.nginx_acc_logs)
    assert.equal("/usr/local/kong/nginx.conf", conf.nginx_conf)
    assert.equal("/usr/local/kong/nginx-kong.conf", conf.nginx_kong_conf)
    assert.equal("/usr/local/kong/kong.conf", conf.kong_conf)
    -- ssl default paths
    assert.equal("/usr/local/kong/ssl/kong-default.crt", conf.ssl_cert_default)
    assert.equal("/usr/local/kong/ssl/kong-default.key", conf.ssl_cert_key_default)
    assert.equal("/usr/local/kong/ssl/kong-default.csr", conf.ssl_cert_csr_default)
  end)
  it("strips comments ending settings", function()
    local conf = assert(conf_loader("spec/fixtures/to-strip.conf"))
    assert.equal("cassandra", conf.database)
    assert.equal("debug", conf.log_level)
  end)
  it("overcomes penlight's list_delim option", function()
    local conf = assert(conf_loader("spec/fixtures/to-strip.conf"))
    assert.False(conf.dnsmasq)
    assert.True(conf.plugins.foobar)
    assert.True(conf.plugins["hello-world"])
  end)

  describe("inferences", function()
    it("infer booleans (on/off/true/false strings)", function()
      local conf = assert(conf_loader())
      assert.equal("on", conf.nginx_daemon)
      assert.equal("on", conf.lua_code_cache)
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
    it("infer ngx_boolean", function()
      local conf = assert(conf_loader(nil, {
        lua_code_cache = true
      }))
      assert.equal("on", conf.lua_code_cache)

      conf = assert(conf_loader(nil, {
        lua_code_cache = false
      }))
      assert.equal("off", conf.lua_code_cache)

      conf = assert(conf_loader(nil, {
        lua_code_cache = "off"
      }))
      assert.equal("off", conf.lua_code_cache)
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
      assert.equal("database has an invalid value: 'mysql' (postgres, cassandra)", err)
      assert.is_nil(conf)

      conf, err = conf_loader(nil, {
        cassandra_consistency = "FOUR"
      })
      assert.equal("cassandra_consistency has an invalid value: 'FOUR'"
                 .." (ALL, EACH_QUORUM, QUORUM, LOCAL_QUORUM, ONE, TWO,"
                 .." THREE, LOCAL_ONE)", err)
      assert.is_nil(conf)
    end)
    it("enforces ipv4:port types", function()
      local conf, err = conf_loader(nil, {
        cluster_listen = 123
      })
      assert.equal("cluster_listen must be in the form of IPv4:port", err)
      assert.is_nil(conf)

      conf, err = conf_loader(nil, {
        cluster_listen = "1.1.1.1"
      })
      assert.equal("cluster_listen must be in the form of IPv4:port", err)
      assert.is_nil(conf)

      conf, err = conf_loader(nil, {
        cluster_listen = "1.1.1.1:3333"
      })
      assert.is_nil(err)
      assert.is_table(conf)
    end)
    it("enforces listen addresses format", function()
      local conf, err = conf_loader(nil, {
        admin_listen = "127.0.0.1"
      })
      assert.is_nil(conf)
      assert.equal("admin_listen must be of form 'address:port'", err)

      conf, err = conf_loader(nil, {
        proxy_listen = "127.0.0.1"
      })
      assert.is_nil(conf)
      assert.equal("proxy_listen must be of form 'address:port'", err)

      conf, err = conf_loader(nil, {
        proxy_listen_ssl = "127.0.0.1"
      })
      assert.is_nil(conf)
      assert.equal("proxy_listen_ssl must be of form 'address:port'", err)
    end)
    it("errors when dns_resolver is not a list in ipv4[:port] format", function()
      local conf, err = conf_loader(nil, {
        dns_resolver = "[::1]:53"
      })
      assert.equal("dns_resolver must be a comma separated list in the form of IPv4 or IPv4:port", err)
      assert.is_nil(conf)

      local conf, err = conf_loader(nil, {
        dns_resolver = "1.2.3.4:53;4.3.2.1" -- ; as separator
      })
      assert.equal("dns_resolver must be a comma separated list in the form of IPv4 or IPv4:port", err)
      assert.is_nil(conf)

      conf, err = conf_loader(nil, {
        dns_resolver = "8.8.8.8,1.2.3.4:53"
      })
      assert.is_nil(err)
      assert.is_table(conf)

      conf, err = conf_loader(nil, {
        dns_resolver = "8.8.8.8:53"
      })
      assert.is_nil(err)
      assert.is_table(conf)
    end)
    it("cluster_ttl_on_failure cannot be lower than 60 seconds", function()
      local conf, err = conf_loader(nil, {
        cluster_ttl_on_failure = 40
      })
      assert.equal("cluster_ttl_on_failure must be at least 60 seconds", err)
      assert.is_nil(conf)
    end)
    it("does not check SSL cert and key if SSL is off", function()
      local conf, err = conf_loader(nil, {
        ssl = false,
        ssl_cert = "/path/cert.pem"
      })
      assert.is_nil(err)
      assert.is_table(conf)
    end)
    it("requires both SSL cert and key", function()
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
end)
