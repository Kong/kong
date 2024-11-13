local schema_def = require "kong.plugins.response-ratelimiting.schema"
local helpers = require "spec.helpers"
local v = helpers.validate_plugin_config_schema

local null = ngx.null


describe("Plugin: response-rate-limiting (schema)", function()
  it("proper config validates", function()
    local config = {limits = {video = {second = 1}}}
    local ok, err = v(config, schema_def)
    assert.truthy(ok)
    assert.is_nil(err)
  end)
  it("proper config validates (bis)", function()
    local config = {limits = {video = {second = 1, minute = 2, hour = 3, day = 4, month = 5, year = 6}}}
    local ok, err = v(config, schema_def)
    assert.truthy(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()
    it("empty config", function()
      local ok, err = v({}, schema_def)
      assert.falsy(ok)
      assert.equal("required field missing", err.config.limits)

      local ok, err = v({ limits = {} }, schema_def)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.config.limits)
    end)
    it("invalid limit", function()
      local config = {limits = {video = {seco = 1}}}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("unknown field", err.config.limits.seco)
    end)
    it("limits: \'null\' value does not cause 500, issue #8314", function()
      local config = {limits = {video = {second = null, minute = 1}}}
      local ok, err = v(config, schema_def)
      assert.truthy(ok)
      assert.falsy(err)
    end)
    it("limits: smaller unit is less than bigger unit", function()
      local config = {limits = {video = {second = 2, minute = 1}}}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("the limit for minute(1.0) cannot be lower than the limit for second(2.0)",
                   err.config.limits)
    end)
    it("limits: smaller unit is less than bigger unit (bis)", function()
      local config = {limits = {video = {second = 1, minute = 2, hour = 3, day = 4, month = 6, year = 5}}}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("the limit for year(5.0) cannot be lower than the limit for month(6.0)",
                   err.config.limits)
    end)
    it("invaldid unit type", function()
      local config = {limits = {second = 10}}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("expected a record", err.config.limits)
    end)

    it("proper config validates with redis new structure", function()
      local config = {
        limits = {
          video = {
            second = 10
          }
        },
        policy = "redis",
        redis = {
          host = helpers.redis_host,
          port = helpers.redis_port,
          database = 0,
          username = "test",
          password = "testXXX",
          ssl = true,
          ssl_verify = false,
          timeout = 1100,
          server_name = helpers.redis_ssl_sni,
      } }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("proper config validates with redis legacy structure", function()
      local config = {
        limits = {
          video = {
            second = 10
          }
        },
        policy = "redis",
        redis_host = helpers.redis_host,
        redis_port = helpers.redis_port,
        redis_database = 0,
        redis_username = "test",
        redis_password = "testXXX",
        redis_ssl = true,
        redis_ssl_verify = false,
        redis_timeout = 1100,
        redis_server_name = helpers.redis_ssl_sni,
      }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("verifies that redis required fields are supplied", function()
      local config = {
        limits = {
          video = {
            second = 10
          }
        },
        policy = "redis",
        redis = {
          port = helpers.redis_port,
          database = 0,
          username = "test",
          password = "testXXX",
          ssl = true,
          ssl_verify = false,
          timeout = 1100,
          server_name = helpers.redis_ssl_sni,
      } }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("required field missing", err.config.redis.host)
    end)
  end)
end)
