-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis = require "kong.enterprise_edition.tools.redis.v2".config_schema
local Entity = require "kong.db.schema.entity"


local ngx_null = ngx.null


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
    local ok, err = process_auto_fields_and_insert({
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("accepts valid redis cluster data", function()
    local ok, err = process_auto_fields_and_insert({
      cluster_addresses = { "127.0.0.1:26379" },
    })

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("accepts combination of all: single, cluster, sentinel", function()
    local ok, err = process_auto_fields_and_insert({
      host = "127.0.0.1",
      port = 6379,
      cluster_addresses = { "127.0.0.1:26379" },
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
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

    local redis_cluster_obj = {
      name = "redis-cluster" .. table.concat(configB.redis.cluster_addresses),
    }

    assert.same("redis-clusterredis:6380", redis_cluster_obj.name)
  end)

  it("errors with invalid redis sentinel data", function()
    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("all or none of these fields must be set: 'sentinel_master'," ..
      " 'sentinel_role', 'sentinel_nodes'", err["@entity"][1])

    local ok, err = Redis:validate_insert({
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("all or none of these fields must be set: 'sentinel_master'," ..
      " 'sentinel_role', 'sentinel_nodes'", err["@entity"][1])

    local ok, err = Redis:validate_insert({
      sentinel_addresses = { "127.0.0.1:26379" },
      sentinel_master = "mymaster",
    })

    assert.is_falsy(ok)
    assert.same("all or none of these fields must be set: 'sentinel_master'," ..
      " 'sentinel_role', 'sentinel_nodes'", err["@entity"][1])

    local ok, err = process_auto_fields_and_insert({
      sentinel_addresses = { "127.0.0.1" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("Invalid Redis host address: 127.0.0.1", err.sentinel_addresses)

    local ok, err = process_auto_fields_and_insert({
      sentinel_addresses = {},
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("length must be at least 1", err.sentinel_addresses)

    local ok, err = process_auto_fields_and_insert({
      sentinel_nodes = {},
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("length must be at least 1", err.sentinel_nodes)

    local ok, err = process_auto_fields_and_insert({
      sentinel_addresses = { "127.0.0.1:12345", "127.0.0.2" },
      sentinel_master = "mymaster",
      sentinel_role = "master",
    })

    assert.is_falsy(ok)
    assert.same("Invalid Redis host address: 127.0.0.2", err.sentinel_addresses)

  end)

  it("errors with invalid redis cluster data", function()
    local ok, err = process_auto_fields_and_insert({
      cluster_addresses = "127.0.0.1:26379"
    })

    assert.is_falsy(ok)
    assert.same("expected an array", err.cluster_addresses)

    local ok, err = process_auto_fields_and_insert({
      cluster_addresses = { "127.0.0.1" },
    })

    assert.is_falsy(ok)
    assert.same("Invalid Redis host address: 127.0.0.1", err.cluster_addresses)

    local ok, err = process_auto_fields_and_insert({
      cluster_addresses = {},
    })

    assert.is_falsy(ok)
    assert.same("length must be at least 1", err.cluster_addresses)

    local ok, err = process_auto_fields_and_insert({
      cluster_nodes = {},
    })

    assert.is_falsy(ok)
    assert.same("length must be at least 1", err.cluster_nodes)
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

  it("supports connection to Redis via proxy", function()
    local good_conf1 = {
      host = "redis",
      port = 6379,
      database = ngx_null,
      connection_is_proxied = true,
    }
    local ok, errs, processed_configuration = process_auto_fields_and_insert(good_conf1)
    assert.is_truthy(ok)
    assert.is_nil(errs)
    assert.is_truthy(processed_configuration)
    assert.are_equal(true, processed_configuration.connection_is_proxied)

    local good_conf2 = {
      host = "redis",
      port = 6379,
      database = 0,
      connection_is_proxied = false,
    }
    ok, errs, processed_configuration = process_auto_fields_and_insert(good_conf2)
    assert.is_truthy(ok)
    assert.is_nil(errs)
    assert.is_truthy(processed_configuration)
    assert.are_equal(false, processed_configuration.connection_is_proxied)

    local bad_conf1 = {
      host = "redis",
      port = 6379,
      database = 0,
      connection_is_proxied = "xyz",
    }
    ok, errs = process_auto_fields_and_insert(bad_conf1)
    assert.is_falsy(ok)
    assert.are_equal("expected a boolean", errs["connection_is_proxied"])

    local bad_conf2 = {
      host = "redis",
      port = 6379,
      database = 1,
      connection_is_proxied = true,
    }
    ok, errs = process_auto_fields_and_insert(bad_conf2)
    assert.is_falsy(ok)
    assert.are_equal("database must be '0' or 'null' when 'connection_is_proxied' is 'true'.", errs["@entity"][1])

    local bad_conf4 = {
      sentinel_nodes = {
        { host = "sentinel0", port = 26379 },
        { host = "sentinel1", port = 26379 },
        { host = "sentinel2", port = 26379 },
      },
      sentinel_master = "mymaster0",
      sentinel_role = "master",
      connection_is_proxied = true
    }
    ok, errs = process_auto_fields_and_insert(bad_conf4)
    assert.is_falsy(ok)
    assert.are_equal("'connection_is_proxied' can not be 'true' when 'sentinel_role' is set.", errs["@entity"][1])

    local bad_conf5 = {
      cluster_nodes = {
        { ip = "127.0.0.1", port = 26379 },
        { ip = "127.0.0.1", port = 26379 },
        { ip = "127.0.0.1", port = 26379 },
      },
      connection_is_proxied = true
    }
    ok, errs = process_auto_fields_and_insert(bad_conf5)
    assert.is_falsy(ok)
    assert.are_equal("'connection_is_proxied' can not be 'true' when 'cluster_nodes' is set.", errs["@entity"][1])
  end)
end)
