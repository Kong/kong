local schema_def = require "spec.fixtures.custom_plugins.kong.plugins.redis-dummy.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Validate standardized redis config schema", function()
  describe("valid  config", function()
    it("accepts minimal redis config (populates defaults)", function()
      local config = {
        redis = {
          host = "localhost"
        }
      }
      local ok, err = v(config, schema_def)
      assert.truthy(ok)
      assert.same({
        host = "localhost",
        port = 6379,
        timeout = 2000,
        username = ngx.null,
        password = ngx.null,
        database = 0,
        ssl = false,
        ssl_verify = false,
        server_name = ngx.null,
      }, ok.config.redis)
      assert.is_nil(err)
    end)

    it("full redis config", function()
      local config = {
        redis = {
          host = "localhost",
          port = 9900,
          timeout = 3333,
          username = "test",
          password = "testXXX",
          database = 5,
          ssl = true,
          ssl_verify = true,
          server_name = "example.test"
        }
      }
      local ok, err = v(config, schema_def)
      assert.truthy(ok)
      assert.same(config.redis, ok.config.redis)
      assert.is_nil(err)
    end)

    it("allows empty strings on password", function()
      local config = {
        redis = {
          host = "localhost",
          password = "",
        }
      }
      local ok, err = v(config, schema_def)
      assert.truthy(ok)
      assert.same({
        host = "localhost",
        port = 6379,
        timeout = 2000,
        username = ngx.null,
        password = "",
        database = 0,
        ssl = false,
        ssl_verify = false,
        server_name = ngx.null,
      }, ok.config.redis)
      assert.is_nil(err)
    end)
  end)

  describe("invalid config", function()
    it("rejects invalid config", function()
      local config = {
        redis = {
          host = "",
          port = -5,
          timeout = -5,
          username = 1,
          password = 4,
          database = "abc",
          ssl = "abc",
          ssl_verify = "xyz",
          server_name = "test-test"
        }
      }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.same({
        config = {
          redis = {
            database = 'expected an integer',
            host = 'length must be at least 1',
            password = 'expected a string',
            port = 'value should be between 0 and 65535',
            ssl = 'expected a boolean',
            ssl_verify = 'expected a boolean',
            timeout = 'value should be between 0 and 2147483646',
            username = 'expected a string',
          }
        }
      }, err)
    end)
  end)
end)
