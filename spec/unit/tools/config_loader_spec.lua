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
    assert.truthy(conf.admin_api_port)
    assert.truthy(conf.proxy_port)
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
      proxy_port = "string",
      database = "cassandra",
      cassandra = {
        contact_points = "127.0.0.1",
        ssl = {
          enabled = "false"
        }
      }
    })
    assert.False(ok)
    assert.truthy(errors)
    assert.equal("must be a number", errors.proxy_port)
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
    assert.equal("must be one of: 'cassandra'", errors.database)
  end)
end)

