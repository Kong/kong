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

  it("errors with invalid redis data", function()
    local ok, err  = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "127.0.0.1",
        port = "foo",
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("port is not a number", err["redis.port"])

    local ok, _, self_error = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        port = 6379,
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same({ message = "Redis host must be provided", schema = true },
                self_error)

    local ok, _, self_error = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "127.0.0.1",
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same({ message = "Redis port must be provided", schema = true },
                self_error)

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

  it("accepts valid redis sentinel data", function()
    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_addresses = "127.0.0.1:26379",
        sentinel_master = "mymaster",
        sentinel_role = "master",
      },
    }, rate_limiting_schema)

    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("errors with invalid redis sentinel data", function()
    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_addresses = "127.0.0.1:26379",
        sentinel_role = "master",
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("You need to specify a Redis Sentinel master", err.redis)

    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_master = "mymaster",
        sentinel_role = "master",
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("You need to specify one or more Redis Sentinel addresses",
                err.redis)

    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_addresses = "127.0.0.1:26379",
        sentinel_master = "mymaster",
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("You need to specify a Redis Sentinel role",  err.redis)

    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_addresses = "127.0.0.1:26379",
        sentinel_master = "mymaster",
        sentinel_role = "master",
        host = "127.0.0.1",
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("When Redis Sentinel is enabled you cannot set a 'redis.host'",
                err.redis)

    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_addresses = "127.0.0.1:26379",
        sentinel_master = "mymaster",
        sentinel_role = "master",
        port = 6379,
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("When Redis Sentinel is enabled you cannot set a 'redis.port'",
                err.redis)

    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_addresses = "127.0.0.1",
        sentinel_master = "mymaster",
        sentinel_role = "master",
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("Invalid Redis Sentinel address: 127.0.0.1", err.redis)

    local ok, err = validate_entity({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_addresses = "127.0.0.1:12345,127.0.0.2",
        sentinel_master = "mymaster",
        sentinel_role = "master",
      },
    }, rate_limiting_schema)

    assert.is_false(ok)
    assert.same("Invalid Redis Sentinel address: 127.0.0.2", err.redis)
  end)
end)
