-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local rate_limiting_schema = require "kong.plugins.service-protection.schema"
local v = require("spec.helpers").validate_plugin_config_schema
local helpers = require "spec.helpers"
local cjson = require "cjson"
local fmt = string.format
local pl_utils = require "pl.utils"
local plugin_name = "service-protection"

local ngx_null = ngx.null

local kong = kong
local concat = table.concat

local conf_err = concat{ "[service-protection] ",
                         "strategy 'cluster' is not supported with Hybrid deployments or DB-less mode. ",
                         "If you did not specify the strategy, please use 'redis' strategy, 'local' strategy ",
                         "or set 'sync_rate' to -1.", }


local function post_config(admin_client, yaml_file)
   local res = assert(admin_client:send {
     method = "POST",
     path = "/config",
     body = {
       config = pl_utils.readfile(yaml_file),
     },
     headers = {
       ["Content-Type"] = "application/json",
     }
   })
   return cjson.decode(assert.res_status(201, res))
end

local function post_plugin(admin_client, config)
  local res = assert(admin_client:send {
    method = "POST",
    path = "/plugins/",
    body = config,
    headers = {
      ["Content-Type"] = "application/json",
    },
  })
  return cjson.decode(assert.res_status(201, res))
end

describe("service-protection schema", function()
  it("timeout does not overwrite connect/read/send timeout to null", function()
    local config, err = v({
      window_size     = { 60 },
      limit           = { 10 },
      strategy        = "redis",
      sync_rate       = 1,
      redis           = {
        host            = "redis",
        port            = 6379,
        timeout         = ngx_null,
        connect_timeout = 3001,
        read_timeout    = 3002,
        send_timeout    = 3003,
      },
    }, rate_limiting_schema)

    assert.is_truthy(config)
    assert.equal("redis", config.config.strategy)
    assert.equal(1, config.config.sync_rate)
    assert.equal(3001, config.config.redis.connect_timeout)
    assert.equal(3002, config.config.redis.read_timeout)
    assert.equal(3003, config.config.redis.send_timeout)
    assert.is_nil(config.config.redis.timeout)
    assert.is_nil(err)
  end)

  it("if new fields contain nulls but timeout does not - overwrite connect/read/send with value of timeout", function()
    local config, err = v({
      window_size     = { 60 },
      limit           = { 10 },
      strategy        = "redis",
      sync_rate       = 1,
      redis           = {
        host            = "redis",
        port            = 6379,
        timeout         = 3005,
        connect_timeout = ngx_null,
        read_timeout    = ngx_null,
        send_timeout    = ngx_null,
      },
    }, rate_limiting_schema)

    assert.is_truthy(config)
    assert.equal("redis", config.config.strategy)
    assert.equal(1, config.config.sync_rate)
    assert.equal(3005, config.config.redis.connect_timeout)
    assert.equal(3005, config.config.redis.read_timeout)
    assert.equal(3005, config.config.redis.send_timeout)
    assert.is_nil(config.config.redis.timeout)
    assert.is_nil(err)
  end)

  it("accepts a minimal config with lock_dictionary_name", function()
    local config, err = v({
      window_size = { 60 },
      limit = { 10 },
      lock_dictionary_name = "kong_test_sp_schema_abcd",
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(config)
    assert.equal("local", config.config.strategy)
    assert.equal("kong_test_sp_schema_abcd", config.config.lock_dictionary_name)
  end)

  it("accepts a minimal config without lock_dictionary_name, fallback to kong_locks", function()
    local config, err = v({
      window_size = { 60 },
      limit = { 10 },
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(config)
    assert.equal("local", config.config.strategy)
    assert.equal("kong_locks", config.config.lock_dictionary_name)
  end)

  it("accepts a minimal config", function()
    local config, err = v({
      window_size = { 60 },
      limit = { 10 },
    }, rate_limiting_schema)

    assert.is_truthy(config)
    assert.equal("local", config.config.strategy)
    assert.is_nil(err)
  end)

  it("accepts a minimal cluster config", function()
    local ok, err = v({
      strategy = "cluster",
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
    }, rate_limiting_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("errors with an invalid size/limit type", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { "foo" },
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "expected a number" }, err.config.limit)
  end)

  it("errors with size/limit number does not match", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 50, 10 },
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "You must provide the same number of windows and limits" }, err["@entity"])
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

    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        cluster_addresses = { "127.0.0.1:26379" }
      },
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        cluster_nodes = {
          { ip = "127.0.0.1", port = 26379 }
        },
        cluster_addresses = { "127.0.0.1:26379" }
      },
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        cluster_nodes = ngx_null,
        cluster_addresses = { "127.0.0.1:26379" }
      },
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        cluster_nodes = {
          { ip = "127.0.0.1", port = 26379 }
        },
        cluster_addresses = ngx_null
      },
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_master = "mymaster",
        sentinel_role = "master",
        sentinel_nodes = {
          { host = "localhost", port = 26379 }
        },
        sentinel_addresses = { "localhost:26379" }
      },
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    -- defaults to host/port
    local entity, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.same(entity.config.redis.host, "127.0.0.1")
    assert.same(entity.config.redis.port, 6379)

    local entity, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "example.com"
      }
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.same(entity.config.redis.host, "example.com")
    assert.same(entity.config.redis.port, 6379)

    local entity, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        port = 7100
      }
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.same(entity.config.redis.host, "127.0.0.1")
    assert.same(entity.config.redis.port, 7100)
  end)

  it("errors with a missing/incomplete redis config", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = ngx.null,
        port = ngx.null
      }
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "No redis config provided" }, err["@entity"])

    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "example.com",
        port = ngx.null
      }
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.is_truthy(err.config.redis["@entity"])

    local ok = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_master = "example.com",
      }
    }, rate_limiting_schema)
    assert.is_falsy(ok)

    local ok = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "example.com",
        port = 6379,
        timeout = 3000,
        connect_timeout = 3000,
        send_timeout = 3000,
        read_timeout = 3001, -- this is different from `timeout` field
      },
    }, rate_limiting_schema)
    assert.is_falsy(ok)

    local ok = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        cluster_nodes = {
          { ip = "127.0.0.1", port = 26380 } -- port differ
        },
        cluster_addresses = { "127.0.0.1:26379" }
      },
    }, rate_limiting_schema)
    assert.is_falsy(ok)

    local ok = v({
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_master = "mymaster",
        sentinel_role = "master",
        sentinel_nodes = {
          { host = "localhost", port = 26380 } -- port differ
        },
        sentinel_addresses = { "localhost:26379" }
      },
    }, rate_limiting_schema)
    assert.is_falsy(ok)
  end)

  it("accepts a hide_client_headers config", function ()
    local ok, err = v({
      window_size = {60},
      limit = {10},
      hide_client_headers = true,
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a retry_after_jitter_max config", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      retry_after_jitter_max = 1,
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("errors with NaN retry_after_jitter_max config", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      retry_after_jitter_max = "not a number",
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same("expected a number", err.config.retry_after_jitter_max)
  end)

  it("errors with a negative retry_after_jitter_max config", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      retry_after_jitter_max = -1,
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "Non-negative retry_after_jitter_max value is expected" }, err["@entity"])
  end)

  it("rejects sync_rate values between 0 and 0.02", function()
    local ok, err = v({
      strategy = "cluster",
      window_size = { 60 },
      limit = { 10 },
      sync_rate = 0.01,
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "Config option 'sync_rate' must not be a decimal between 0 and 0.02" }, err["@entity"])
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

  it("accepts a local strategy", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "local",
      -- sync_rate is no longer required
    }, rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    -- a local strategy automatically sets sync_rate to -1
    assert.same(-1, ok.config.sync_rate)
  end)

  it("rejects a local strategy with sync_rate different than -1", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "local",
      sync_rate = 1,
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "sync_rate cannot be configured when using a local strategy" }, err["@entity"])
  end)

  it("accepts a local strategy with sync_rate set to -1", function()
    local ok, _ = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "local",
      sync_rate = -1,
    }, rate_limiting_schema)

    assert.is_truthy(ok)
    assert.same(-1, ok.config.sync_rate)
  end)

  it("sync_rate is required if not using a local strategy", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "sync_rate is required if not using a local strategy" }, err["@entity"])
  end)
end)

describe("DB-less mode schema validation", function()
  local db_bak = kong.configuration.database

  lazy_setup(function()
    rawset(kong.configuration, "database", "off")
  end)

  lazy_teardown(function()
    rawset(kong.configuration, "database", db_bak)
  end)

  it("rejects a cluster strategy with DB-less mode", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
      sync_rate = 1,
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ conf_err }, err["@entity"])
  end)

  it("accepts the cluster strategy with DB-less mode when sync_rate is -1", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
      sync_rate = -1,
    }, rate_limiting_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
end)

describe("Hybrid mode schema validation", function()
  local role_bak = kong.configuration.role

  lazy_setup(function()
    rawset(kong.configuration, "role", "hybrid")
  end)

  lazy_teardown(function()
    rawset(kong.configuration, "role", role_bak)
  end)

  it("rejects a cluster strategy with DB-less mode", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
      sync_rate = 1,
    }, rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ conf_err }, err["@entity"])
  end)

  it("accepts the cluster strategy with Hybrid mode when sync_rate is -1", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
      sync_rate = -1,
    }, rate_limiting_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
end)

for _, strategy in helpers.all_strategies() do
  describe(fmt("%s - namespace configuration consistency [#%s]", plugin_name, strategy), function()
    local bp, admin_client
    local config1, config2
    local yaml_file_0, yaml_file_2
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "routes",
        "services",
        "plugins",
      }, { plugin_name })

      -- two plugins with the same namespace but different configs
      config1 = {
        name = plugin_name,
        config = {
          namespace = "foo",
          strategy = "redis",
          window_size = { 5 },
          limit = { 3 },
          sync_rate = 0.5,
          redis = {
            host = "invalid.test",  -- different
            port = helpers.redis_port,
            database = 1,
          },
        },
      }

      config2 = {
        name = plugin_name,
        config = {
          namespace = "foo",
          strategy = "redis",
          window_size = { 5 },
          limit = { 3 },
          sync_rate = 0.5,
          redis = {
            host = "invalid2.test", -- different
            port = helpers.redis_port,
            database = 1,
          },
        },
      }

      if strategy == "off" then
        yaml_file_0 = helpers.make_yaml_file()

        bp.plugins:insert(config1)

        yaml_file_2 = helpers.make_yaml_file()
      end

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and yaml_file_0 or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      helpers.clean_logfile()
      if admin_client then
        admin_client:close()
      end
    end)

    it("should not have error log after changing to the same configuration", function()
      if strategy == "off" then
        post_config(admin_client, yaml_file_2)

      else
        post_plugin(admin_client, config2)

      end

      assert.logfile().has.no.line("multiple service-protection plugins with the namespace 'foo' have different counter syncing configurations", true, 5)
    end)
  end)
end
