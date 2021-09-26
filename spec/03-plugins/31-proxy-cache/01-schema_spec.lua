local proxy_cache_schema = require "kong.plugins.proxy-cache.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("proxy-cache schema", function()
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

    assert.same({ "value should be between 100 and 900" }, err.config.response_code)
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

    assert.same({ "expected an integer", "expected an integer" },
                err.config.response_code)
    assert.is_falsy(entity)
  end)

  it("errors if response_code has float value", function()
    local entity, err = v({
      strategy = "memory",
      response_code = {123.5},
    }, proxy_cache_schema)

    assert.same({ "expected an integer" }, err.config.response_code)
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
  it("accepts a minimal redis config", function()
    local entity, err = v({
      strategy = "redis",
      redis= { host = "test.com" },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)
  it("error if redis conf is missing with redis strategy", function()
    local entity, err = v({
      strategy = "redis",
    }, proxy_cache_schema)

    assert.same("required field missing", err.config.redis.host)
    assert.is_falsy(entity)
  end)
  it("error if host is missing with redis strategy", function()
    local entity, err = v({
      strategy = "redis",
      redis = { port = 1234 },
    }, proxy_cache_schema)

    assert.same("required field missing", err.config.redis.host)
    assert.is_falsy(entity)
  end)
  it("error if host is invalid", function()
    local entity, err = v({
      strategy = "redis",
      redis = { host = 123 },
    }, proxy_cache_schema)

    assert.same("expected a string", err.config.redis.host)
    assert.is_falsy(entity)
  end)
  it("error if host is invalid", function()
    local entity, err = v({
      strategy = "redis",
      redis = { host = "300.0.0.120" },
    }, proxy_cache_schema)

    assert.same("invalid value: 300.0.0.120", err.config.redis.host)
    assert.is_falsy(entity)
  end)
  it("error if host is invalid", function()
    local entity, err = v({
      strategy = "redis",
      redis = { host = "10.0.0.12:660" },
    }, proxy_cache_schema)

    assert.same("must not have a port", err.config.redis.host)
    assert.is_falsy(entity)
  end)
  it("error if port is invalid", function()
    local entity, err = v({
      strategy = "redis",
      redis = { port = -123 },
    }, proxy_cache_schema)

    assert.same("value should be between 0 and 65535", err.config.redis.port)
    assert.is_falsy(entity)
  end)
  it("accepts a full redis config", function()
    local entity, err = v({
      strategy = "redis",
      redis = {
        host = "test.com",
        port = 1234,
        timeout = 100,
        database = 3,
      }
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)
end)
