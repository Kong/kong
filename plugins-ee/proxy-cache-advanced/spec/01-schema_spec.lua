-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local proxy_cache_schema = require "kong.plugins.proxy-cache-advanced.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("proxy-cache-advanced schema", function()
  it("accepts a minimal config", function()
    local entity, err = v({
      strategy = "memory",
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("defines default content-type values", function()
    local config = {strategy = "memory"}
    local entity, err = v(config, proxy_cache_schema)
    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.same(entity.config.content_type, {"text/plain", "application/json"})
  end)

  it("accepts a config with custom values", function()
    local entity, err = v({
      strategy = "memory",
      response_code = { 200, 301 },
      request_method = { "GET" },
      content_type = { "application/json" },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("accepts an array of numbers as strings", function()
    local entity, err = v({
      strategy = "memory",
      response_code = {123, 200},
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("errors with invalid response_code", function()
    local entity, err = v({
      strategy = "memory",
      response_code = { 99 },
    }, proxy_cache_schema)

    assert.same("value should be between 100 and 900", err.config.response_code[1])
    assert.is_falsy(entity)
  end)

  it("errors if response_code is an empty array", function()
    local entity, err = v({
      strategy = "memory",
      response_code = {},
    }, proxy_cache_schema)

    assert.same("length must be at least 1", err.config.response_code)
    assert.is_falsy(entity)
  end)

  it("errors if response_code is a string", function()
    local entity, err = v({
      strategy = "memory",
      response_code = "",
    }, proxy_cache_schema)

    assert.same("expected an array", err.config.response_code)
    assert.is_falsy(entity)
  end)

  it("errors if response_code has non-numeric values", function()
    local entity, err = v({
      strategy = "memory",
      response_code = {true, "alo", 123},
    }, proxy_cache_schema)

    assert.same("expected an integer", err.config.response_code[1])
    assert.same("expected an integer", err.config.response_code[2])
    assert.is_falsy(entity)
  end)

  it("errors if response_code has float value", function()
    local entity, err = v({
      strategy = "memory",
      response_code = {123.5},
    }, proxy_cache_schema)

    assert.same("expected an integer", err.config.response_code[1])
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

  it("accepts a redis config", function()
    local entity, err = v({
      strategy = "redis",
      redis = {
        host = "127.0.0.1",
        port = 6379,
      },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)

    local ok, err = v({
      strategy = "redis",
      redis = {
        cluster_addresses = { "127.0.0.1:26379" }
      },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    -- empty redis config - fallbacks to defaults
    local entity, err = v({
      strategy = "redis",
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.same(entity.config.redis.host, "127.0.0.1")
    assert.same(entity.config.redis.port, 6379)
  end)

  it("errors with a missing redis config", function()
    local entity, err = v({
      strategy = "redis",
      redis = {
        host = ngx.null,
        port = ngx.null
      }
    }, proxy_cache_schema)

    assert.is_same("No redis config provided", err["@entity"][1])
    assert.is_falsy(entity)
  end)

  it("supports vary_query_params values", function()
    local entity, err = v({
      strategy = "memory",
      vary_query_params = { "foo" },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("supports vary_headers values", function()
    local entity, err = v({
      strategy = "memory",
      vary_headers = { "foo" },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("accepts wildcard content_type", function()
    local entity, err = v({
      strategy = "memory",
      content_type = { "application/*", "*/text" },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)

    local entity, err = v({
      strategy = "memory",
      content_type = { "*/*" },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("accepts content_type with parameter", function()
    local entity, err = v({
      strategy = "memory",
      content_type = { "application/json; charset=UTF-8" },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)
end)
