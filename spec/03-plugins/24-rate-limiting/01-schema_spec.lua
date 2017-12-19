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

  it("accepts a redis config", function()
    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "127.0.0.1",
        port = 6379,
      },
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("errors with a missing redis config", function()
    local ok, _, self_error = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same({ message = "No redis config provided", schema = true },
                self_error)
  end)

  it("accepts a hide_client_headers config", function ()
    local ok, err = validate_entity({
      window_size = {60},
      limit = {10},
      sync_rate = 10,
      hide_client_headers = true,
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("transparently sorts the limit/window_size pairs", function()
    local config = {
      limit = {
        100, 10,
      },
      window_size = {
        3600, 60
      },
      sync_rate = 0,
      strategy = "cluster",
    }
    local ok, err = validate_entity(config, rate_limiting_schema)

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({ 10, 100 }, config.limit)
    assert.same({ 60, 3600 }, config.window_size)

    local config = {
      limit = {
        10, 5,
      },
      window_size = {
        3600, 60,
      },
      sync_rate = 0,
      strategy = "cluster",
    }
    local ok, err = validate_entity(config, rate_limiting_schema)

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({ 5, 10 }, config.limit)
    assert.same({ 60, 3600 }, config.window_size)


    -- show we are sorting explicitly based on limit
    -- this configuration doesnt actually make sense
    -- but for tests purposes we need to verify our behavior
    local config = {
      limit = {
        100, 10,
      },
      window_size = {
        60, 3600
      },
      sync_rate = 0,
      strategy = "cluster",
    }
    local ok, err = validate_entity(config, rate_limiting_schema)

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({ 10, 100 }, config.limit)
    assert.same({ 3600, 60 }, config.window_size)

    -- slightly more complex example
    local config = {
      limit = {
        100, 1000, 10,
      },
      window_size = {
        3600, 86400, 60
      },
      sync_rate = 0,
      strategy = "cluster",
    }
    local ok, err = validate_entity(config, rate_limiting_schema)

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({ 10, 100, 1000 }, config.limit)
    assert.same({ 60, 3600, 86400 }, config.window_size)
  end)
end)
