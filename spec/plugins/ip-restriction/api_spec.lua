local schemas_validation = require "kong.dao.schemas_validation"
local schema = require "kong.plugins.ip-restriction.schema"

local v = schemas_validation.validate_entity

describe("ip-restriction schema", function()
  describe("errors", function()
    it("whitelist should not accept invalid types", function()
      local t = {whitelist = 12}
      local ok, err = v(t, schema)
      assert.False(ok)
      assert.same({whitelist = "whitelist is not a array"}, err)
    end)
    it("whitelist should not accept invalid IPs", function()
      local t = {whitelist = "hello"}
      local ok, err = v(t, schema)
      assert.False(ok)
      assert.same({whitelist = "cannot parse 'hello': Invalid IP"}, err)

      t = {whitelist = {"127.0.0.1", "127.0.0.2", "hello"}}
      ok, err = v(t, schema)
      assert.False(ok)
      assert.same({whitelist = "cannot parse 'hello': Invalid IP"}, err)
    end)
    it("blacklist should not accept invalid types", function()
      local t = {blacklist = 12}
      local ok, err = v(t, schema)
      assert.False(ok)
      assert.same({blacklist = "blacklist is not a array"}, err)
    end)
    it("blacklist should not accept invalid IPs", function()
      local t = {blacklist = "hello"}
      local ok, err = v(t, schema)
      assert.False(ok)
      assert.same({blacklist = "cannot parse 'hello': Invalid IP"}, err)

      t = {blacklist = {"127.0.0.1", "127.0.0.2", "hello"}}
      ok, err = v(t, schema)
      assert.False(ok)
      assert.same({blacklist = "cannot parse 'hello': Invalid IP"}, err)
    end)
    it("should not accept both a whitelist and a blacklist", function()
      local t = {blacklist = {"127.0.0.1"}, whitelist = {"127.0.0.2"}}
      local ok, err, self_err = v(t, schema)
      assert.False(ok)
      assert.falsy(err)
      assert.equal("you cannot set both a whitelist and a blacklist", self_err.message)
    end)
    it("should not accept both empty whitelist and blacklist", function()
      local t = {blacklist = {}, whitelist = {}}
      local ok, err, self_err = v(t, schema)
      assert.False(ok)
      assert.falsy(err)
      assert.equal("you must set at least a whitelist or blacklist", self_err.message)
    end)
  end)
  describe("ok", function()
    it("should accept a valid whitelist", function()
      local t = {whitelist = {"127.0.0.1", "127.0.0.2"}}
      local ok, err = v(t, schema)
      assert.True(ok)
      assert.falsy(err)
    end)
    it("should accept a valid blacklist", function()
      local t = {blacklist = {"127.0.0.1", "127.0.0.2"}}
      local ok, err = v(t, schema)
      assert.True(ok)
      assert.falsy(err)
    end)
  end)
end)
