local schemas_validation = require "kong.dao.schemas_validation"
local schema             = require "kong.plugins.ip-restriction.schema"


local v = schemas_validation.validate_entity


describe("Plugin: ip-restriction (schema)", function()
  it("should accept a valid whitelist", function()
    assert(v({whitelist = {"127.0.0.1", "127.0.0.2"}}, schema))
  end)
  it("should accept a valid blacklist", function()
    assert(v({blacklist = {"127.0.0.1", "127.0.0.2"}}, schema))
  end)

  describe("errors", function()
    it("whitelist should not accept invalid types", function()
      local ok, err = v({whitelist = 12}, schema)
      assert.False(ok)
      assert.same({whitelist = "whitelist is not an array"}, err)
    end)
    it("whitelist should not accept invalid IPs", function()
      local ok, err = v({whitelist = "hello"}, schema)
      assert.False(ok)
      assert.same({whitelist = "cannot parse 'hello': Invalid IP"}, err)

      ok, err = v({whitelist = {"127.0.0.1", "127.0.0.2", "hello"}}, schema)
      assert.False(ok)
      assert.same({whitelist = "cannot parse 'hello': Invalid IP"}, err)
    end)
    it("blacklist should not accept invalid types", function()
      local ok, err = v({blacklist = 12}, schema)
      assert.False(ok)
      assert.same({blacklist = "blacklist is not an array"}, err)
    end)
    it("blacklist should not accept invalid IPs", function()
      local ok, err = v({blacklist = "hello"}, schema)
      assert.False(ok)
      assert.same({blacklist = "cannot parse 'hello': Invalid IP"}, err)

      ok, err = v({blacklist = {"127.0.0.1", "127.0.0.2", "hello"}}, schema)
      assert.False(ok)
      assert.same({blacklist = "cannot parse 'hello': Invalid IP"}, err)
    end)
    it("should not accept both a whitelist and a blacklist", function()
      local t = {blacklist = {"127.0.0.1"}, whitelist = {"127.0.0.2"}}
      local ok, err, self_err = v(t, schema)
      assert.False(ok)
      assert.is_nil(err)
      assert.equal("you cannot set both a whitelist and a blacklist", self_err.message)
    end)
    it("should not accept both empty whitelist and blacklist", function()
      local t = {blacklist = {}, whitelist = {}}
      local ok, err, self_err = v(t, schema)
      assert.False(ok)
      assert.is_nil(err)
      assert.equal("you must set at least a whitelist or blacklist", self_err.message)
    end)
  end)
end)
