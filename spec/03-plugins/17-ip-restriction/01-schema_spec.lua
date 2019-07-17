local schema_def = require "kong.plugins.ip-restriction.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: ip-restriction (schema)", function()
  it("should accept a valid whitelist", function()
    assert(v({ whitelist = { "127.0.0.1", "127.0.0.2" } }, schema_def))
  end)
  it("should accept a valid cidr range", function()
    assert(v({ whitelist = { "127.0.0.1/8" } }, schema_def))
  end)
  it("should accept a valid blacklist", function()
    assert(v({ blacklist = { "127.0.0.1", "127.0.0.2" } }, schema_def))
  end)

  describe("errors", function()
    it("whitelist should not accept invalid types", function()
      local ok, err = v({ whitelist = 12 }, schema_def)
      assert.falsy(ok)
      assert.same({ whitelist = "expected an array" }, err.config)
    end)
    it("whitelist should not accept invalid IPs", function()
      local ok, err = v({ whitelist = { "hello" } }, schema_def)
      assert.falsy(ok)
      assert.same({ whitelist = { "invalid cidr range: Invalid IP" } }, err.config)

      ok, err = v({ whitelist = { "127.0.0.1", "127.0.0.2", "hello" } }, schema_def)
      assert.falsy(ok)
      assert.same({ whitelist = { [3] = "invalid cidr range: Invalid IP" } }, err.config)
    end)
    it("blacklist should not accept invalid types", function()
      local ok, err = v({ blacklist = 12 }, schema_def)
      assert.falsy(ok)
      assert.same({ blacklist = "expected an array" }, err.config)
    end)
    it("blacklist should not accept invalid IPs", function()
      local ok, err = v({ blacklist = { "hello" } }, schema_def)
      assert.falsy(ok)
      assert.same({ blacklist = { "invalid cidr range: Invalid IP" } }, err.config)

      ok, err = v({ blacklist = { "127.0.0.1", "127.0.0.2", "hello" } }, schema_def)
      assert.falsy(ok)
      assert.same({ blacklist = { [3] = "invalid cidr range: Invalid IP" } }, err.config)
    end)
    it("should not accept both a whitelist and a blacklist", function()
      local t = { blacklist = { "127.0.0.1" }, whitelist = { "127.0.0.2" } }
      local ok, err = v(t, schema_def)
      assert.falsy(ok)
      assert.same({ "only one of these fields must be non-empty: 'config.whitelist', 'config.blacklist'" }, err["@entity"])
    end)
    it("should not accept both empty whitelist and blacklist", function()
      local t = { blacklist = {}, whitelist = {} }
      local ok, err = v(t, schema_def)
      assert.falsy(ok)
      local expected = {
        "only one of these fields must be non-empty: 'config.whitelist', 'config.blacklist'",
        "at least one of these fields must be non-empty: 'config.whitelist', 'config.blacklist'",
      }
      assert.same(expected, err["@entity"])
    end)
    it("should not accept invalid cidr ranges", function()
      local ok, err = v({ whitelist = { "0.0.0.0/a", "0.0.0.0/-1", "0.0.0.0/33" } }, schema_def)
      assert.falsy(ok)
      assert.same({
        whitelist = {
          "invalid cidr range: Invalid prefix: /a",
          "invalid cidr range: Invalid prefix: /-1",
          "invalid cidr range: Invalid prefix: /33",
        }
      }, err.config)

    end)
    it("should not accept invalid ipv6 cidr ranges", function()
      local ok, err = v({ whitelist = { "::/a", "::/-1", "::/129", "::1/a", "::1/-1", "::1/129" } }, schema_def)
      assert.falsy(ok)
      assert.same({
        whitelist = {
          "invalid cidr range: Invalid prefix: /a",
          "invalid cidr range: Invalid prefix: /-1",
          "invalid cidr range: Invalid prefix: /129",
          "invalid cidr range: Invalid prefix: /a",
          "invalid cidr range: Invalid prefix: /-1",
          "invalid cidr range: Invalid prefix: /129",
        }
      }, err.config)
    end)
    it("should not accept valid ipv6 cidr ranges", function()
      local ok, err = v({ whitelist = { "::/0",  "::/1", "::/128"  } }, schema_def)
      assert.falsy(ok)
      assert.same({
        whitelist = {
          "invalid cidr range: Invalid IP",
          "invalid cidr range: Invalid IP",
          "invalid cidr range: Invalid prefix: /128",
        }
      }, err.config)
    end)
  end)
end)
