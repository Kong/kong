local schema_def = require "kong.plugins.response-ratelimiting.schema"
local v = require("spec.helpers").validate_plugin_config_schema


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
  end)
end)
