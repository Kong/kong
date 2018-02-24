local validate_entity = require("kong.dao.schemas_validation").validate_entity
local cors_schema = require "kong.plugins.cors.schema"

describe("cors schema", function()
  it("validates '*'", function()
    local ok, err = validate_entity({ origins = { "*" } }, cors_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)

  it("validates what looks like a domain", function()
    local ok, err = validate_entity({ origins = { "example.com" } }, cors_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)

  it("validates what looks like a regex", function()
    local ok, err = validate_entity({ origins = { [[.*\.example(?:-foo)?\.com]] } }, cors_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)

  describe("errors", function()
    it("with invalid regex in origins", function()
      local mock_origins = { [[.*.example.com]], [[invalid_**regex]] }
      local ok, err = validate_entity({ origins = mock_origins }, cors_schema)

      assert.False(ok)
      assert.equals("origin '" .. mock_origins[2] .. "' is not a valid regex", err.origins)
    end)
  end)
end)
