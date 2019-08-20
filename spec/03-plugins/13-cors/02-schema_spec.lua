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
