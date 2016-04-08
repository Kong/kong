local IO = require "kong.tools.io"
local yaml = require "yaml"
local spec_helper = require "spec.spec_helpers"
local config = require "kong.tools.config_loader"

local TEST_CONF_PATH = spec_helper.get_env().conf_file

describe("Configuration validation", function()
  it("should validate the default configuration", function()
    local test_config = yaml.load(IO.read_file(TEST_CONF_PATH))
    local ok, errors = config.validate(test_config)
    assert.True(ok)
    assert.falsy(errors)
  end)
  it("should populate defaults", function()
    local conf = {}
    local ok, errors = config.validate(conf)
    assert.True(ok)
    assert.falsy(errors)

    assert.truthy(conf.custom_plugins)
    assert.truthy(conf.admin_api_listen)
    assert.truthy(conf.proxy_listen)
    assert.truthy(conf.proxy_listen_ssl)
    assert.truthy(conf.cluster_listen)
    assert.truthy(conf.cluster_listen_rpc)
    assert.truthy(conf.database)
    assert.truthy(conf.cassandra)

    local function check_defaults(conf, conf_defaults)
      for k, v in pairs(conf) do
        if conf_defaults[k].type == "table" then
          check_defaults(v, conf_defaults[k].content)
        end
        if conf_defaults[k].default ~= nil then
          assert.equal(conf_defaults[k].default, v)
        end
      end
    end

    check_defaults(conf, require("kong.tools.config_defaults"))
  end)
  it("should populate the plugins property", function()
    local config = config.load(TEST_CONF_PATH)
    assert.truthy(config)
    assert.equal(0, #config.custom_plugins)
    assert.truthy(#config.plugins > 0)
  end)
  it("should validate various types", function()
    local ok, errors = config.validate({
      proxy_listen = 123,
      database = 777,
      cassandra = {
        contact_points = "127.0.0.1",
        ssl = {
          enabled = "false"
        }
      }
    })
    assert.False(ok)
    assert.truthy(errors)
    assert.equal("must be a string", errors.proxy_listen)
    assert.equal("must be a string", errors.database[1])
    assert.equal("must be one of: 'cassandra, postgres'", errors.database[2])
    assert.equal("must be a array", errors["cassandra.contact_points"])
    assert.equal("must be a boolean", errors["cassandra.ssl.enabled"])
    assert.falsy(errors.ssl_cert_path)
    assert.falsy(errors.ssl_key_path)
  end)
  it("should check for minimum allowed value if is a number", function()
    local ok, errors = config.validate({memory_cache_size = 16})
    assert.False(ok)
    assert.equal("must be greater than 32", errors.memory_cache_size)
  end)
  it("should check that the value is contained in `enum`", function()
    local ok, errors = config.validate({
      cassandra = {
        replication_strategy = "foo"
      }
    })
    assert.False(ok)
    assert.equal("must be one of: 'SimpleStrategy, NetworkTopologyStrategy'", errors["cassandra.replication_strategy"])
  end)
  it("should validate the selected database property", function()
    local ok, errors = config.validate({database = "foo"})
    assert.False(ok)
    assert.equal("must be one of: 'cassandra, postgres'", errors.database)
  end)
  describe("database: cassandra", function()
    it("should accept proper cassandra properties", function()
      local valids = {
        {
          contact_points = {"127.0.0.1:9042", "120.0.0.2:9042"},
          keyspace = "kong",
          replication_strategy = "SimpleStrategy"
        },
        {
          contact_points = {"127.0.0.1:9042"},
          keyspace = "kong_development",
          replication_strategy = "NetworkTopologyStrategy",
          data_centers = {"dc1", "dc2"},
          username = "cassandra",
          password = "cassandra",
          ssl = {
            enabled = true,
            verify = false,
            certificate_authority = "/path/to/certificate.ca"
          }
        }
      }

      for _, v in ipairs(valids) do
        local c = {
          database = "cassandra",
          cassandra = v
        }
        local ok, errors = config.validate(c)
        assert.falsy(errors)
        assert.True(ok)
      end
    end)
    it("should not accept invalid cassandra properties", function()
      local invalids = {
        {
          contact_points = "127.0.0.1:9042",
          keyspace = "kong",
          replication_strategy = "foo"
        },
        {
          contact_points = {"127.0.0.1:9042"},
          keyspace = "kong_development",
          replication_strategy = "NetworkTopologyStrategy",
          data_centers = {"dc1", "dc2"},
          username = "cassandra",
          password = "cassandra",
          ssl = {
            enabled = "true",
            verify = false,
            certificate_authority = "/path/to/certificate.ca"
          }
        }
      }

      for _, v in ipairs(invalids) do
        local c = {
          database = "cassandra",
          cassandra = v
        }
        local ok, errors = config.validate(c)
        assert.False(ok)
        assert.truthy(errors)
      end
    end)
  end)
  describe("database: postgres", function()
    it("should accept proper postgres properties", function()
      local valids = {
        {
          host = "127.0.0.1",
          port = 5423,
          user = "postgres",
          database = "kong"
        },
        {
          host = "190.168.1.0",
          port = 6000,
          user = "kong",
          database = "kong_development"
        }
      }

      for _, v in ipairs(valids) do
        local c = {
          database = "postgres",
          postgres = v
        }
        local ok, errors = config.validate(c)
        assert.falsy(errors)
        assert.True(ok)
      end
    end)
    it("should not accept invalid postgres properties", function()
      local invalids = {
        {
          host = "127.0.0.1",
          port = "5423",
          user = "postgres",
          database = "kong"
        },
        {
          host = "190.168.1.0",
          port = 6000,
          user = "kong",
          database = 123
        }
      }

      for _, v in ipairs(invalids) do
        local c = {
          database = "postgres",
          postgres = v
        }
        local ok, errors = config.validate(c)
        assert.False(ok)
        assert.truthy(errors)
      end
    end)
  end)
  it("should validate the selected dns_resolver property", function()
    local ok, errors = config.validate({dns_resolver = "foo"})
    assert.False(ok)
    assert.equal("must be one of: 'server, dnsmasq'", errors.dns_resolver)
  end)
  it("should validate the host:port listen addresses", function()
    -- Missing port
    local ok, errors = config.validate({proxy_listen = "foo"})
    assert.False(ok)
    assert.equal("foo is not a valid \"host:port\" value", errors.proxy_listen)

    -- Port invalid
    ok, errors = config.validate({proxy_listen = "foo:asd"})
    assert.False(ok)
    assert.equal("foo:asd is not a valid \"host:port\" value", errors.proxy_listen)

    -- Port too large
    ok, errors = config.validate({proxy_listen = "foo:8000000"})
    assert.False(ok)
    assert.equal("foo:8000000 is not a valid \"host:port\" value", errors.proxy_listen)

    -- Only port
    ok, errors = config.validate({proxy_listen = "1231"})
    assert.False(ok)
    assert.equal("1231 is not a valid \"host:port\" value", errors.proxy_listen)

    -- Only semicolon and port
    ok, errors = config.validate({proxy_listen = ":1231"})
    assert.False(ok)
    assert.equal(":1231 is not a valid \"host:port\" value", errors.proxy_listen)

    -- Valid with hostname
    ok, errors = config.validate({proxy_listen = "hello:1231"})
    assert.True(ok)
    assert.falsy(errors)

    -- Valid with IP
    ok, errors = config.validate({proxy_listen = "1.1.1.1:1231"})
    assert.True(ok)
    assert.falsy(errors)
  end)
  it("should validate the ip:port listen addresses", function()
    -- Hostname instead of IP
    local ok, errors = config.validate({cluster_listen = "hello.com:1231"})
    assert.False(ok)
    assert.equal("hello.com:1231 is not a valid \"ip:port\" value", errors.cluster_listen)

    -- Invalid IP
    ok, errors = config.validate({cluster_listen = "777.1.1.1:1231"})
    assert.False(ok)
    assert.equal("777.1.1.1:1231 is not a valid \"ip:port\" value", errors.cluster_listen)

    -- Valid
    ok, errors = config.validate({cluster_listen = "1.1.1.1:1231"})
    assert.True(ok)
    assert.falsy(errors)

    -- Invalid cluster.advertise
    ok, errors = config.validate({cluster={advertise = "1"}})
    assert.False(ok)
    assert.equal("1 is not a valid \"ip:port\" value", errors["cluster.advertise"])

    -- Valid cluster.advertise
    ok, errors = config.validate({cluster={advertise = "1.1.1.1:1231"}})
    assert.True(ok)
    assert.falsy(errors)
  end)
end)

