local schema_def = require "kong.plugins.cors.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("origins in cors schema", function()
  it("validates '*'", function()
    local ok, err = v({ origins = { "*" } }, schema_def)

    assert.truthy(ok)
    assert.falsy(err)
  end)

  it("validates what looks like a domain", function()
    local ok, err = v({ origins = { "example.com" } }, schema_def)

    assert.truthy(ok)
    assert.falsy(err)
  end)

  it("validates what looks like a regex", function()
    local ok, err = v({ origins = { [[.*\.example(?:-foo)?\.com]] } }, schema_def)

    assert.truthy(ok)
    assert.falsy(err)
  end)

  describe("errors", function()
    it("with invalid regex in origins", function()
      local mock_origins = { [[.*.example.com]], [[invalid_**regex]] }
      local ok, err = v({ origins = mock_origins }, schema_def)

      assert.falsy(ok)
      assert.equals("'invalid_**regex' is not a valid regex",
                    err.config.origins[2])
    end)
  end)
end)


describe("methods in cors schema", function()
  for _, method in ipairs({ "HEAD", "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "TRACE", "CONNECT" }) do
    it("should allow " .. method, function()
      local ok, err = v({ methods = { method } }, schema_def)

      assert.truthy(ok)
      assert.falsy(err)
    end)
  end

  describe("errors", function()
    it("with invalid method", function()
      local ok, err = v({ methods = { "FAKE" } }, schema_def)

      assert.falsy(ok)
      assert.equals("expected one of: GET, HEAD, PUT, PATCH, POST, DELETE, OPTIONS, TRACE, CONNECT",
                    err.config.methods[1])
    end)
  end)
end)
