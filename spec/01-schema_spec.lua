local rate_limiting_schema = require "kong.plugins.rate-limiting-advanced.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("rate-limiting-advanced schema", function()
  it("accepts a minimal config", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a config with a custom identifier", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      identifier = "consumer",
      sync_rate = 10,
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("casts window_size and window_limit values to numbers", function()
    local schema = {
      window_size = { 10, 20 },
      limit = { 50, 75 },
      identifier = "consumer",
      sync_rate = 10,
    }

    local ok, err = v(schema, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    for _, window_size in ipairs(schema.window_size) do
      assert.is_number(window_size)
    end

    for _, limit in ipairs(schema.limit) do
      assert.is_number(limit)
    end
  end)

  it("errors with an invalid size/limit type", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { "foo" },
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same("expected a number", err.config.limit)
  end)

  it("accepts a redis config", function()
    local ok, err = v({
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
    assert.is_truthy(ok)
  end)

  it("errors with a missing redis config", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same("required field missing", err.config.redis.host)

    ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "example.com",
      }
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same("All or none of 'host', 'port' must be set. Only 'host' found",
                 err.config.redis["@entity"][1])
  end)

  it("accepts a hide_client_headers config", function ()
    local ok, err = v({
      window_size = {60},
      limit = {10},
      sync_rate = 10,
      hide_client_headers = true,
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
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
    local ok, err = v(config, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    table.sort(config.limit)
    table.sort(config.window_size)

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
    local ok, err = v(config, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    table.sort(config.limit)
    table.sort(config.window_size)

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
    local ok, err = v(config, rate_limiting_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
    assert.same({ 10, 100 }, ok.config.limit)
    assert.same({ 3600, 60 }, ok.config.window_size)

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
    local ok, err = v(config, rate_limiting_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
    assert.same({ 10, 100, 1000 }, ok.config.limit)
    assert.same({ 60, 3600, 86400 }, ok.config.window_size)
  end)
end)
