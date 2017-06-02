local schemas = require "kong.dao.schemas_validation"
local plugin_schema = require "kong.plugins.response-ratelimiting.schema"
local validate_entity = schemas.validate_entity

describe("Plugin: response-rate-limiting (schema)", function()
  it("proper config validates", function()
    local config = {limits = {video = {second = 1}}}
    local ok, err = validate_entity(config, plugin_schema)
    assert.True(ok)
    assert.is_nil(err)
  end)
  it("proper config validates (bis)", function()
    local config = {limits = {video = {second = 1, minute = 2, hour = 3, day = 4, month = 5, year = 6}}}
    local ok, err = validate_entity(config, plugin_schema)
    assert.True(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()
    it("empty config", function()
      local config = {}
      local ok, _, err = validate_entity(config, plugin_schema)
      assert.False(ok)
      assert.equal("You need to set at least one limit name", err.message)
    end)
    it("invalid limit", function()
      local config = {limits = {video = {seco = 1}}}
      local ok, err = validate_entity(config, plugin_schema)
      assert.False(ok)
      assert.equal("seco is an unknown field", err["limits.video.seco"])
    end)
    it("limits: smaller unit is less than bigger unit", function()
      local config = {limits = {video = {second = 2, minute = 1}}}
      local ok, _, self_check_err = validate_entity(config, plugin_schema)
      assert.False(ok)
      assert.equal("The limit for minute cannot be lower than the limit for second", self_check_err.message)
    end)
    it("limits: smaller unit is less than bigger unit (bis)", function()
      local config = {limits = {video = {second = 1, minute = 2, hour = 3, day = 4, month = 6, year = 5}}}
      local ok, _, self_check_err = validate_entity(config, plugin_schema)
      assert.False(ok)
      assert.equal("The limit for year cannot be lower than the limit for month", self_check_err.message)
    end)
    it("invaldid unit type", function()
      local config = {limits = {second = 10}}
      local ok, err = validate_entity(config, plugin_schema)
      assert.False(ok)
      assert.equal("second is not a table", err["limits.second"])
    end)
  end)
end)
