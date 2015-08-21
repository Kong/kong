local schemas = require "kong.dao.schemas_validation"
local validate_entity = schemas.validate_entity

local plugin_schema = require "kong.plugins.response-ratelimiting.schema"

describe("Response Rate Limiting schema", function()

  it("should be invalid when no value is being set", function()
    local values = {}
    local valid, _, err = validate_entity(values, plugin_schema)
    assert.falsy(valid)
    assert.are.equal("You need to set at least one limit name", err.message)
  end)

  it("should work when the proper value is being set", function()
    local values = { limits = { second = 10 } }
    local valid, err = validate_entity(values, plugin_schema)
    assert.falsy(valid)
    assert.are.equal("second is not a table", err["limits.second"])
  end)

  it("should work when the proper value is being set", function()
    local values = { limits = { video = { seco = 1 } } }
    local valid, err = validate_entity(values, plugin_schema)
    assert.falsy(valid)
    assert.are.equal("seco is an unknown field", err["limits.video.seco"])
  end)

  it("should work when the proper value is being set", function()
    local values = { limits = { video = { second = 2, minute = 1 } } }
    local valid, _, self_check_err = validate_entity(values, plugin_schema)
    assert.falsy(valid)
    assert.are.equal("The value for minute cannot be lower than the value for second", self_check_err.message)
  end)

  it("should work when the proper value are being set", function()
    local values = { limits = { video = { second = 1, minute = 2 } } }
    local valid, err = validate_entity(values, plugin_schema)
    assert.truthy(valid)
    assert.falsy(err)
  end)

end)