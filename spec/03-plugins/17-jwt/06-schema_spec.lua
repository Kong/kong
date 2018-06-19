local validate_entity = require("kong.dao.schemas_validation").validate_entity
local jwt_schema = require "kong.plugins.jwt.schema"


describe("Plugin: jwt (schema)", function()
  it("validates 'maximum_expiration'", function()
    local ok, err = validate_entity({
      maximum_expiration = 60,
      claims_to_verify = { "exp", "nbf" },
    }, jwt_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  describe("errors", function()
    it("when 'maximum_expiration' is negative", function()
      local ok, err = validate_entity({
        maximum_expiration = -1,
        claims_to_verify = { "exp", "nbf" },
      }, jwt_schema)

      assert.is_false(ok)
      assert.same({
        maximum_expiration = "should be 0 or greater"
      }, err)

      local ok, err = validate_entity({
        maximum_expiration = -1,
        claims_to_verify = { "nbf" },
      }, jwt_schema)

      assert.is_false(ok)
      assert.same({
        maximum_expiration = "should be 0 or greater"
      }, err)
    end)

    it("when 'maximum_expiration' is specified without 'exp' in 'claims_to_verify'", function()
      local ok, err, self_err = validate_entity({
        maximum_expiration = 60,
        claims_to_verify = { "nbf" },
      }, jwt_schema)

      assert.is_false(ok)
      assert.is_nil(err)
      assert.same({
        message = "claims_to_verify must contain 'exp' when specifying maximum_expiration",
        schema = true,
      }, self_err)
    end)
  end)
end)
