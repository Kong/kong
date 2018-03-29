local schemas          = require "kong.dao.schemas_validation"
local hmac_auth_schema = require "kong.plugins.hmac-auth.schema"
local validate_entity  = schemas.validate_entity


describe("Plugin: hmac-auth (schema)", function()
  it("accepts empty config", function()
    local ok, err = validate_entity({}, hmac_auth_schema)
    assert.is_nil(err)
    assert.is_true(ok)
  end)
  it("accepts correct clock skew", function()
    local ok, err = validate_entity({clock_skew = 10}, hmac_auth_schema)
    assert.is_nil(err)
    assert.is_true(ok)
  end)
  it("errors with negative clock skew", function()
    local ok, err = validate_entity({clock_skew = -10}, hmac_auth_schema)
    assert.equal("Clock Skew should be positive", err.clock_skew)
    assert.is_false(ok)
  end)
  it("errors with wrong algorithm", function()
    local ok, err = validate_entity({algorithms = {"sha1024"}}, hmac_auth_schema)
    assert.equal('"sha1024" is not allowed. Allowed values are: "hmac-sha1", "hmac-sha256", "hmac-sha384", "hmac-sha512"', err.algorithms)
    assert.is_false(ok)
  end)
end)
