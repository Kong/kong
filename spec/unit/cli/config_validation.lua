local IO = require "kong.tools.io"
local yaml = require "yaml"
local spec_helper = require "spec.spec_helpers"
local config_validation = require "kong.cli.config_validation"

local TEST_CONF_PATH = spec_helper.get_env().conf_file

describe("Configuration validation", function()
  it("should validate the default configuration", function()
    local test_config = yaml.load(IO.read_file(TEST_CONF_PATH))
    local ok, errors = config_validation(test_config)
    assert.True(ok)
    assert.falsy(errors)
  end)
  it("should populate defaults", function()
    local config = {}
    local ok, errors = config_validation(config)
    assert.True(ok)
    assert.falsy(errors)

    assert.truthy(config.admin_api_port)
    assert.truthy(config.proxy_port)
    assert.truthy(config.database)
    assert.truthy(config.databases_available)
    assert.equal("table", type(config.databases_available))
    assert.equal("localhost:9042", config.databases_available.cassandra.properties.contact_points[1])
  end)
  it("should validate various types", function()
    local ok, errors = config_validation({
      proxy_port = "string",
      database = 666,
      databases_available = {
        cassandra = {
          properties = {
            timeout = "foo",
            ssl = "true"
          }
        }
      }
    })
    assert.False(ok)
    assert.truthy(errors)
    assert.equal("must be a number", errors.proxy_port)
    assert.equal("must be a string", errors.database)
    assert.equal("must be a number", errors["databases_available.cassandra.properties.timeout"])
    assert.equal("must be a boolean", errors["databases_available.cassandra.properties.ssl"])
    assert.falsy(errors.ssl_cert_path)
    assert.falsy(errors.ssl_key_path)
  end)
end)

