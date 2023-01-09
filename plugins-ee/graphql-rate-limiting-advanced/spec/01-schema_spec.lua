-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
end)
