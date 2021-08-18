local schema_def = require "kong.plugins.ip-restriction.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: ip-restriction (schema)", function()
  it("should accept a valid allow", function()
    assert(v({ allow = { "127.0.0.1", "127.0.0.2" } }, schema_def))
  end)
  it("should accept a valid allow and status/message", function()
    assert(v({ allow = { "127.0.0.1", "127.0.0.2" }, status = 403, message = "Forbidden" }, schema_def))
  end)
  it("should accept a valid cidr range", function()
    assert(v({ allow = { "127.0.0.1/8" } }, schema_def))
  end)
  it("should accept a valid deny", function()
    assert(v({ deny = { "127.0.0.1", "127.0.0.2" } }, schema_def))
  end)
  it("should accept both non-empty allow and deny", function()
    local schema = {
      deny = {
        "127.0.0.2"
      },
      allow = {
        "127.0.0.1"
      },
    }
    assert(v(schema, schema_def))
  end)

  describe("errors", function()
    it("allow should not accept invalid types", function()
      local ok, err = v({ allow = 12 }, schema_def)
      assert.falsy(ok)
      assert.same({ allow = "expected an array" }, err.config)
    end)
    it("allow should not accept invalid IPs", function()
      local ok, err = v({ allow = { "hello" } }, schema_def)
      assert.falsy(ok)
      assert.same({
        allow = { "invalid ip or cidr range: 'hello'" }
      }, err.config)

      ok, err = v({ allow = { "127.0.0.1", "127.0.0.2", "hello" } }, schema_def)
      assert.falsy(ok)
      assert.same({
        allow = { [3] = "invalid ip or cidr range: 'hello'" }
      }, err.config)
    end)
    it("deny should not accept invalid types", function()
      local ok, err = v({ deny = 12 }, schema_def)
      assert.falsy(ok)
      assert.same({ deny = "expected an array" }, err.config)
    end)
    it("deny should not accept invalid IPs", function()
      local ok, err = v({ deny = { "hello" } }, schema_def)
      assert.falsy(ok)
      assert.same({
        deny = { "invalid ip or cidr range: 'hello'" }
      }, err.config)

      ok, err = v({ deny = { "127.0.0.1", "127.0.0.2", "hello" } }, schema_def)
      assert.falsy(ok)
      assert.same({
        deny = { [3] = "invalid ip or cidr range: 'hello'" }
      }, err.config)
    end)
    it("should not accept both empty allow and deny", function()
      local t = { deny = {}, allow = {} }
      local ok, err = v(t, schema_def)
      assert.falsy(ok)
      local expected = {
        "at least one of these fields must be non-empty: 'config.allow', 'config.deny'",
      }
      assert.same(expected, err["@entity"])
    end)

    it("should not accept invalid cidr ranges", function()
      local ok, err = v({ allow = { "0.0.0.0/a", "0.0.0.0/-1", "0.0.0.0/33" } }, schema_def)
      assert.falsy(ok)
      assert.same({
        allow = {
          "invalid ip or cidr range: '0.0.0.0/a'",
          "invalid ip or cidr range: '0.0.0.0/-1'",
          "invalid ip or cidr range: '0.0.0.0/33'",
        }
      }, err.config)
    end)
    it("should not accept invalid ipv6 cidr ranges", function()
      local ok, err = v({ allow = { "::/a", "::/-1", "::/129", "::1/a", "::1/-1", "::1/129" } }, schema_def)
      assert.falsy(ok)
      assert.same({
        allow = {
          "invalid ip or cidr range: '::/a'",
          "invalid ip or cidr range: '::/-1'",
          "invalid ip or cidr range: '::/129'",
          "invalid ip or cidr range: '::1/a'",
          "invalid ip or cidr range: '::1/-1'",
          "invalid ip or cidr range: '::1/129'",
        }
      }, err.config)
    end)

    it("should accept valid ipv6 cidr ranges", function()
      local ok = v({ allow = { "::/0",  "::/1", "::/128"  } }, schema_def)
      assert.truthy(ok)
    end)
  end)
end)
