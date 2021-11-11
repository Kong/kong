-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local proxy_cache_schema = require "kong.plugins.graphql-proxy-cache-advanced.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("graphql-proxy-cache-advanced schema", function()
  it("accepts a minimal config", function()
    local entity, err = v({
      strategy = "memory",
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("accepts cache ttl config parameter", function()
    local entity, err = v({
      strategy = "memory",
      cache_ttl = 10
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("errors with invalid strategy", function()
    local entity, err = v({
      strategy = "redis"
    }, proxy_cache_schema)

    assert.same("expected one of: memory", err.config.strategy)
    assert.is_falsy(entity)
  end)

  it("errors with invalid ttl", function()
    local entity, err = v({
      strategy = "memory",
      cache_ttl = -1
    }, proxy_cache_schema)

    assert.same("value must be greater than 0", err.config.cache_ttl)
    assert.is_falsy(entity)
  end)
end)
