local schemas = require "kong.dao.schemas_validation"
local validate_entity = schemas.validate_entity

local plugin_schema = require "kong.plugins.ratelimiting.schema"

describe("Rate Limiting schema", function()

  it("should be invalid when no value is being set", function()
    local values = {}
    local valid, _, err = validate_entity(values, plugin_schema)
    assert.falsy(valid)
    assert.are.equal("You need to set at least one limit: second, minute, hour, day, month, year", err.message)
  end)

  it("should work when the proper value is being set", function()
    local values = { second = 10 }
    local valid, _, err = validate_entity(values, plugin_schema)
    assert.truthy(valid)
    assert.falsy(err)
  end)

  it("should work when the proper value are being set", function()
    local values = { second = 10, hour = 20 }
    local valid, _, err = validate_entity(values, plugin_schema)
    assert.truthy(valid)
    assert.falsy(err)
  end)

  it("should not work when invalid data is being set", function()
    local values = { second = 20, hour = 10 }
    local valid, _, err = validate_entity(values, plugin_schema)
    assert.falsy(valid)
    assert.are.equal("The value for hour cannot be lower than the value for second", err.message)
  end)
  
end)