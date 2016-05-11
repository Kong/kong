local schemas = require "kong.dao.schemas_validation"
local validate_entity = schemas.validate_entity

local plugin_schema = require "kong.plugins.rate-limiting.schema"

describe("Rate Limiting schema", function()

  it("should be invalid when no config is being set", function()
    local config = {}
    local valid, _, err = validate_entity(config, plugin_schema)
    assert.falsy(valid)
    assert.are.equal("You need to set at least one limit: second, minute, hour, day, month, year", err.message)
  end)

  it("should work when the proper config is being set", function()
    local config = { second = 10 }
    local valid, _, err = validate_entity(config, plugin_schema)
    assert.truthy(valid)
    assert.falsy(err)
  end)

  it("should work when the proper config are being set", function()
    local config = { second = 10, hour = 20 }
    local valid, _, err = validate_entity(config, plugin_schema)
    assert.truthy(valid)
    assert.falsy(err)
  end)

  it("should not work when invalid data is being set", function()
    local config = { second = 20, hour = 10 }
    local valid, _, err = validate_entity(config, plugin_schema)
    assert.falsy(valid)
    assert.are.equal("The limit for hour cannot be lower than the limit for second", err.message)
  end)

end)
