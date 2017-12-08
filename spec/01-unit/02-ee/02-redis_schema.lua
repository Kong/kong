local validate_entity = require("kong.dao.schemas_validation").validate_entity
local redis_schema = require "kong.enterprise_edition.redis".config_schema

describe("redis schema", function()
  it("errors with invalid redis data", function()
    local ok, err  = validate_entity({
      host = "127.0.0.1",
      port = "foo",
    }, redis_schema)

    assert.is_false(ok)
    assert.same("port is not a number", err.port)

    local ok, _, err = validate_entity({
      port = 6379,
    }, redis_schema)

    assert.is_false(ok)
    assert.same("Redis host must be provided", err.message)

    local ok, _, err = validate_entity({
      host = "127.0.0.1",
    }, redis_schema)

    assert.is_false(ok)
    assert.same("Redis port must be provided", err.message)
  end)

  it("accepts valid redis sentinel data", function()
    local ok, err = validate_entity({
      sentinel_addresses = "127.0.0.1:26379",
      sentinel_master = "mymaster",
      sentinel_role = "master",
    }, redis_schema)

    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("errors with invalid redis sentinel data", function()
    local ok, _, err = validate_entity({
      sentinel_addresses = "127.0.0.1:26379",
      sentinel_role = "master",
    }, redis_schema)

    assert.is_false(ok)
    assert.same("You need to specify a Redis Sentinel master", err.message)

    local ok, _, err = validate_entity({
      sentinel_master = "mymaster",
      sentinel_role = "master",
    }, redis_schema)

    assert.is_false(ok)
    assert.same("You need to specify one or more Redis Sentinel addresses",
                err.message)

    local ok, _, err = validate_entity({
      sentinel_addresses = "127.0.0.1:26379",
      sentinel_master = "mymaster",
    }, redis_schema)

    assert.is_false(ok)
    assert.same("You need to specify a Redis Sentinel role",  err.message)

    local ok, _, err = validate_entity({
      sentinel_addresses = "127.0.0.1:26379",
      sentinel_master = "mymaster",
      sentinel_role = "master",
      host = "127.0.0.1",
    }, redis_schema)

    assert.is_false(ok)
    assert.same("When Redis Sentinel is enabled you cannot set a 'redis.host'",
                err.message)

    local ok, _, err = validate_entity({
      sentinel_addresses = "127.0.0.1:26379",
      sentinel_master = "mymaster",
      sentinel_role = "master",
      port = 6379,
    }, redis_schema)

    assert.is_false(ok)
    assert.same("When Redis Sentinel is enabled you cannot set a 'redis.port'",
                err.message)

    local ok, _, err = validate_entity({
      sentinel_addresses = "127.0.0.1",
      sentinel_master = "mymaster",
      sentinel_role = "master",
    }, redis_schema)

    assert.is_false(ok)
    assert.same("Invalid Redis Sentinel address: 127.0.0.1", err.message)

    local ok, _, err = validate_entity({
      sentinel_addresses = "127.0.0.1:12345,127.0.0.2",
      sentinel_master = "mymaster",
      sentinel_role = "master",
    }, redis_schema)

    assert.is_false(ok)
    assert.same("Invalid Redis Sentinel address: 127.0.0.2", err.message)

  end)
end)
