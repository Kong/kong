local schemas = require "kong.dao.schemas_validation"
local plugin_schema = require "kong.plugins.rate-limiting.schema"
local validate_entity = schemas.validate_entity

describe("Plugin: rate-limiting (schema)", function()
  it("proper config validates", function()
    local config = {second = 10}
    local ok, _, err = validate_entity(config, plugin_schema)
    assert.True(ok)
    assert.is_nil(err)
  end)
  it("proper config validates (bis)", function()
    local config = {second = 10, minute = 20, hour = 30, day = 40, month = 50, year = 60}
    local ok, _, err = validate_entity(config, plugin_schema)
    assert.True(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()
    it("limits: smaller unit is less than bigger unit", function()
      local config = {second = 20, hour = 10}
      local ok, _, err = validate_entity(config, plugin_schema)
      assert.False(ok)
      assert.equal("The limit for hour cannot be lower than the limit for second", err.message)
    end)
    it("limits: smaller unit is less than bigger unit (bis)", function()
      local config = {second = 10, minute = 20, hour = 30, day = 40, month = 60, year = 50}
      local ok, _, err = validate_entity(config, plugin_schema)
      assert.False(ok)
      assert.equal("The limit for year cannot be lower than the limit for month", err.message)
    end)

    it("invalid limit", function()
      local config = {}
      local ok, _, err = validate_entity(config, plugin_schema)
      assert.False(ok)
      assert.equal("You need to set at least one limit: second, minute, hour, day, month, year", err.message)
    end)
  end)
end)
