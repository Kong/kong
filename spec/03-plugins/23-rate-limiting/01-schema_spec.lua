local schema_def = require "kong.plugins.rate-limiting.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: rate-limiting (schema)", function()
  it("proper config validates", function()
    local config = { second = 10 }
    local ok, _, err = v(config, schema_def)
    assert.truthy(ok)
    assert.is_nil(err)
  end)
  it("proper config validates (bis)", function()
    local config = { second = 10, minute = 20, hour = 30, day = 40, month = 50, year = 60 }
    local ok, _, err = v(config, schema_def)
    assert.truthy(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()
    it("limits: smaller unit is less than bigger unit", function()
      local config = { second = 20, hour = 10 }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("The limit for hour(10.0) cannot be lower than the limit for second(20.0)", err.config)
    end)
    it("limits: smaller unit is less than bigger unit (bis)", function()
      local config = { second = 10, minute = 20, hour = 30, day = 40, month = 60, year = 50 }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("The limit for year(50.0) cannot be lower than the limit for month(60.0)", err.config)
    end)

    it("invalid limit", function()
      local config = {}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.same({"at least one of these fields must be non-empty: 'config.second', 'config.minute', 'config.hour', 'config.day', 'config.month', 'config.year'" },
                  err["@entity"])
    end)
  end)
  describe("errors", function()
    it("redis: both redis sentinel and host fields are empty", function()
      local config = { second = 10, hour = 20 , policy = "redis", redis = {sentinel_addresses = nil, host = nil }}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("at least one of these fields must be non-empty: 'config.redis.sentinel_addresses', 'config.redis.host'", err["@entity"][1])
    end)
    it("redis: redis sentinel is an empty array", function()
      local config = { second = 10, hour = 20 , policy = "redis", redis = {sentinel_addresses = {} }}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("length must be at least 1", err.config.redis["sentinel_addresses"])
    end)
    it("redis: redis read_timeout is zero", function()
      local config = { second = 10, hour = 20 , policy = "redis", redis = {sentinel_addresses = {"redis-master:23769","redis-slave:23769"} ,read_timeout = 0}}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("value must be greater than 0", err.config.redis["read_timeout"])
    end)
    it("redis: redis connect_timeout is zero", function()
      local config = { second = 10, hour = 20 , policy = "redis", redis = {sentinel_addresses = {"redis-master:23769","redis-slave:23769"} ,read_timeout = 1000, connect_timeout = 0, password=nil}}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("value must be greater than 0", err.config.redis["connect_timeout"])
    end)
  end)
end)
