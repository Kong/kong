local schemas_validation = require "kong.dao.schemas_validation"
local schema = require "kong.plugins.method-restriction.schema"

local v = schemas_validation.validate_entity

describe("Plugin: method-restriction (schema)", function()
  it("should accept a valid whitelist", function()
    assert(v({whitelist = {"GET", "POST"}}, schema))
  end)
  it("should accept a valid blacklist", function()
    assert(v({blacklist = {"GET", "POST"}}, schema))
  end)

  describe("errors", function()
    it("whitelist should not accept invalid types", function()
      local ok, err = v({whitelist = 12}, schema)
      assert.False(ok)
      assert.same({whitelist = "whitelist is not an array"}, err)
    end)
    it("blacklist should not accept invalid types", function()
      local ok, err = v({blacklist = 12}, schema)
      assert.False(ok)
      assert.same({blacklist = "blacklist is not an array"}, err)
    end)
    it("should not accept both a whitelist and a blacklist", function()
      local t = {blacklist = {"GET"}, whitelist = {"POST"}}
      local ok, err, self_err = v(t, schema)
      assert.False(ok)
      assert.is_nil(err)
      assert.equal("You cannot set both a whitelist and a blacklist", self_err.message)
    end)
    it("should not accept both empty whitelist and blacklist", function()
      local t = {blacklist = {}, whitelist = {}}
      local ok, err, self_err = v(t, schema)
      assert.False(ok)
      assert.is_nil(err)
      assert.equal("You must set at least a whitelist or blacklist", self_err.message)
    end)
  end)

end)
