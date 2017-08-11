local validate_entity = require("kong.dao.schemas_validation").validate_entity
local rate_limiting_schema = require "kong.plugins.rate-limiting.schema"

describe("rate-limiting schema", function()
  it("accepts a minimal config", function()
    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("accepts a config with a custom identifier", function()
    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      identifier = "consumer",
      sync_rate = 10,
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("errors with an invalid size/limit type", function()
    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { "foo" },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("size/limit values must be numbers", err.limit)
  end)
end)
