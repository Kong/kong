local redis = require "kong.enterprise_edition.redis".config_schema
local Entity = require "kong.db.schema.entity"
local redis_connection = require "kong.enterprise_edition.redis".connection
local redis_init_conf = require "kong.enterprise_edition.redis".init_conf

require("resty.dns.client").init(nil)

describe("redis schema", function()
  local Redis = assert(Entity.new(redis))

  it("errors with invalid redis data", function()
    local ok, err  = Redis:validate_insert({
      host = "127.0.0.1",
      port = "foo",
    })

    assert.is_falsy(ok)
    assert.same("expected an integer", err.port)

    local ok, err = Redis:validate_insert({
      port = 6379,
    })

    assert.is_falsy(ok)
    assert.same("all or none of these fields must be set: 'host', 'port'",
                err["@entity"][1])

    local ok, err = Redis:validate_insert({
      host = "127.0.0.1",
    })

    assert.is_falsy(ok)
    assert.same("all or none of these fields must be set: 'host', 'port'",
                err["@entity"][1])
  end)

  it("accepts valid redis sentinel data", function()
    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("accepts valid redis cluster data", function()
    local ok, err = Redis:validate_insert({
      cluster_addresses = { "127.0.0.1:26379" },
    })

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("redis clusters need to be specific to a configuration", function()
    -- Simulate the creation of a plugin configuration with redis cluster
    local configA = {
      redis = {
        cluster_addresses = { "redis:6379" },
      }
    }

    redis_init_conf(configA.redis)
    local connectionA = redis_connection(configA.redis)
    assert.same("redis-clusterredis:6379", connectionA.config.name)

    -- Simulate the creation of another plugin configuration with redis cluster
    local configB = {
      redis = {
        cluster_addresses = { "redis:6380" },
      }
    }

    redis_init_conf(configB.redis)
    local connectionB = redis_connection(configB.redis)
    assert.same("redis-clusterredis:6380", connectionB.config.name)

    -- Make sure that `cluster_addresses` is sorted
    local configC = {
      redis = {
        cluster_addresses = {
          "redis:6380",
          "redis:6379",
        }
      }
    }

    redis_init_conf(configC.redis)
    local connectionC = redis_connection(configC.redis)
    assert.same("redis-clusterredis:6379redis:6380", connectionC.config.name)
  end)

  it("errors with invalid redis sentinel data", function()
    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("all or none of these fields must be set: 'sentinel_master'," ..
      " 'sentinel_role', 'sentinel_addresses'", err["@entity"][1])

    local ok, err = Redis:validate_insert({
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("all or none of these fields must be set: 'sentinel_master'," ..
      " 'sentinel_role', 'sentinel_addresses'", err["@entity"][1])

    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_master = "mymaster",
    })

    assert.is_falsy(ok)
    assert.same("all or none of these fields must be set: 'sentinel_master'," ..
      " 'sentinel_role', 'sentinel_addresses'", err["@entity"][1])

    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
      host = "127.0.0.1",
    })

    assert.is_falsy(ok)
    assert.same("these sets are mutually exclusive: ('sentinel_master'," ..
      " 'sentinel_role', 'sentinel_addresses'), ('host')", err["@entity"][1])

    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
      port = 6379,
    })

    assert.is_falsy(ok)
    assert.same("these sets are mutually exclusive: ('sentinel_master'," ..
      " 'sentinel_role', 'sentinel_addresses'), ('port')", err["@entity"][1])

    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("Invalid Redis host address: 127.0.0.1", err.sentinel_addresses)

    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1:12345", "127.0.0.2" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("Invalid Redis host address: 127.0.0.2", err.sentinel_addresses)

  end)

  it("errors with invalid redis cluster data", function()
    local ok, err = Redis:validate_insert({
      cluster_addresses = "127.0.0.1:26379"
    })

    assert.is_falsy(ok)
    assert.same("expected an array", err.cluster_addresses)

    local ok, err = Redis:validate_insert({
      cluster_addresses = { "127.0.0.1:26379" },
      host = "127.0.0.1",
      port = 6578,
    })

    assert.is_falsy(ok)
    assert.same("these sets are mutually exclusive: ('cluster_addresses')," ..
      " ('host', 'port')", err["@entity"][1])

    local ok, err = Redis:validate_insert({
      cluster_addresses = { "127.0.0.1" },
    })

    assert.is_falsy(ok)
    assert.same("Invalid Redis host address: 127.0.0.1", err.cluster_addresses)

    local ok, err = Redis:validate_insert({
      cluster_addresses = { "127.0.0.1:26379" },
      sentinel_addresses = { "127.0.0.1:12345" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("these sets are mutually exclusive: ('sentinel_master'," ..
      " 'sentinel_role', 'sentinel_addresses'), ('cluster_addresses')", err["@entity"][1])
  end)
end)
