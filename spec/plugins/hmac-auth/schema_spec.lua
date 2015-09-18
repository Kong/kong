local schemas = require "kong.dao.schemas_validation"
local validate_entity = schemas.validate_entity

local hmac_auth_schema = require "kong.plugins.hmac-auth.schema"

describe("HMAC Authentication schema", function()

  it("should work when the clock skew config is being set", function()
    local config = {}
    local valid, err = validate_entity(config, hmac_auth_schema)
    assert.truthy(valid)
    assert.falsy(err)
  end)

  it("should work when the clock skew config is being set", function()
    local config = { clock_skew = 10 }
    local valid, err = validate_entity(config, hmac_auth_schema)
    assert.truthy(valid)
    assert.falsy(err)
  end)
  
  it("should be invalid when negative clock skew being set", function()
    local config = { clock_skew = -10 }
    local valid, err = validate_entity(config, hmac_auth_schema)
    assert.falsy(valid)
    assert.are.equal("Clock Skew should be positive", err.clock_skew)
  end)
end)
