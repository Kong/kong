-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local stringx = require("pl.stringx")
local v = require("spec.helpers").validate_plugin_config_schema
local graphql_rate_limiting_advanced_schema = require "kong.plugins.graphql-rate-limiting-advanced.schema"

local concat = table.concat
local kong = kong

describe("DB-less mode schema validation", function()
  local db_bak = kong.configuration.database

  lazy_setup(function()
    rawset(kong.configuration, "database", "off")
  end)

  lazy_teardown(function()
    rawset(kong.configuration, "database", db_bak)
  end)

  it("accepts the cluster strategy with DB-less mode when sync_rate is -1", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
      sync_rate = -1,
    }, graphql_rate_limiting_advanced_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("rejects the cluster strategy with DB-less mode", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
      sync_rate = 0,
    }, graphql_rate_limiting_advanced_schema)

    assert.is_falsy(ok)
    assert.same({ concat{ "Strategy 'cluster' is not supported with DB-less mode. ",
                          "If you did not specify the strategy, please use the 'redis' strategy ",
                          "or set 'sync_rate' to -1.", }, }, err["@entity"])
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

  it("accepts the cluster strategy with Hybrid mode when sync_rate is -1", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
      sync_rate = -1,
    }, graphql_rate_limiting_advanced_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("rejects the cluster strategy with Hybrid mode", function()
    local ok, err = v({
      window_size = { 60 },
      limit = { 10 },
      strategy = "cluster",
      sync_rate = 0,
    }, graphql_rate_limiting_advanced_schema)

    assert.is_falsy(ok)
    assert.same({ concat{ "Strategy 'cluster' is not supported with Hybrid deployments. ",
                          "If you did not specify the strategy, please use the 'redis' strategy ",
                          "or set 'sync_rate' to -1.", }, }, err["@entity"])
  end)

  describe("accepts the redis strategy", function()
    local redis_conf_map = {
      ['single-node'] = {
        host = '1.1.1.1', port = 12345,
      },
      ['sentinel'] = {
        sentinel_role = 'master',
        sentinel_addresses = {'1.1.1.1:12345', '1.1.1.2:23456'},
        sentinel_master = '1.1.1.1:12345',
      },
      ['single-cluster'] = {
        cluster_addresses = {'1.1.1.1:12345'},
      },
      ['cluster'] = {
        cluster_addresses = {'1.1.1.1:12345', '1.1.1.2:23456'},
      },
      ['failed_if_more_than_one'] = {
        host = '1.1.1.1', port = 12345,
        cluster_addresses = {'1.1.1.1:12345', '1.1.1.2:23456'},
      },
      ['failed_no_redis_conf'] = {},
    }
    for mode, cf in pairs(redis_conf_map) do
      it("in " .. mode .. " mode", function()
        local ok, err = v({
          window_size = { 60 },
          limit = { 10 },
          strategy = "redis",
          sync_rate = -1,
          redis = cf
        }, graphql_rate_limiting_advanced_schema)
        if stringx.startswith(mode, "failed") then
          assert.not_nil(err)
        else
          assert.is_truthy(ok)
          assert.is_nil(err)
        end
      end)
    end
  end)
end)
