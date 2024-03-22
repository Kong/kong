-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis = require "kong.enterprise_edition.redis".config_schema
local Entity = require "kong.db.schema.entity"
local redis_init_conf = require "kong.enterprise_edition.redis".init_conf

local Redis = assert(Entity.new(redis))

local function process_auto_fields_and_insert(conf)
  local processed_configuration, err = Redis:process_auto_fields(conf, "insert")
  if not processed_configuration then
    return nil, err
  end
  local ok, err = Redis:validate(processed_configuration)

  return ok, err, processed_configuration
end

describe("redis schema", function()
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

    local redis_cluster_obj = {
      name = "redis-cluster" .. table.concat(configA.redis.cluster_addresses),
    }

    assert.same("redis-clusterredis:6379", redis_cluster_obj.name)

    -- Simulate the creation of another plugin configuration with redis cluster
    local configB = {
      redis = {
        cluster_addresses = { "redis:6380" },
      }
    }

    redis_init_conf(configB.redis)

    local redis_cluster_obj = {
      name = "redis-cluster" .. table.concat(configB.redis.cluster_addresses),
    }

    assert.same("redis-clusterredis:6380", redis_cluster_obj.name)
  end)

  it("cluster_addresses must be sorted", function()
    local config = {
      redis = {
        cluster_addresses = {
          "redis:6379",
          "redis:6375",
          "redis:6378",
          "redis:6376",
          "redis:6377",
        }
      }
    }

    local expected = {
      "redis:6375",
      "redis:6376",
      "redis:6377",
      "redis:6378",
      "redis:6379",
    }

    redis_init_conf(config.redis)
    assert.same(expected, config.redis.cluster_addresses)
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

  it("granular timeouts have defaults", function()
    local ok, errs, processed_configuration = process_auto_fields_and_insert({})

    assert.is_nil(errs)
    assert.truthy(ok)

    assert.same(2000, processed_configuration.connect_timeout)
    assert.same(2000, processed_configuration.send_timeout)
    assert.same(2000, processed_configuration.read_timeout)
  end)

  it("accepts deprecated timeout", function()
    local conf = {
      timeout = 42,
    }

    local ok, errs, processed_configuration = process_auto_fields_and_insert(conf)

    assert.is_nil(errs)
    assert.truthy(ok)

    assert.same(conf.timeout, processed_configuration.connect_timeout)
    assert.same(conf.timeout, processed_configuration.send_timeout)
    assert.same(conf.timeout, processed_configuration.read_timeout)
  end)

  it("accepts granular timeouts", function()
    local conf = {
      connect_timeout = 42,
      send_timeout = 84,
      read_timeout = 168,
    }

    local ok, errs, processed_configuration = process_auto_fields_and_insert(conf)

    assert.is_nil(errs)
    assert.truthy(ok)
    assert.same(conf.connect_timeout, processed_configuration.connect_timeout)
    assert.same(conf.send_timeout, processed_configuration.send_timeout)
    assert.same(conf.read_timeout, processed_configuration.read_timeout)
  end)

  it("rejects invalid keepalive_pool_size", function()
    for _, pool_size in ipairs({ -1, 0, math.pow(2, 31) }) do
      local ok, errs = Redis:validate({ keepalive_pool_size = pool_size })
      assert.falsy(ok)
      assert.same("value should be between 1 and 2147483646", errs["keepalive_pool_size"])
    end
  end)

  it("rejects invalid backlog", function()
    for _, backlog in ipairs({ -1, math.pow(2, 31) }) do
      local ok, errs = Redis:validate({ keepalive_backlog = backlog })
      assert.falsy(ok)
      assert.same("value should be between 0 and 2147483646", errs["keepalive_backlog"])
    end
  end)
end)
