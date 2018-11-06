local validate_entity    = require("kong.dao.schemas_validation").validate_entity
local proxy_cache_schema = require "kong.plugins.proxy-cache.schema"

describe("proxy-cache schema", function()
  it("accepts a minimal config", function()
    local ok, err = validate_entity({
      strategy = "memory",
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("defines default content-type values", function()
    local config = {strategy = "memory"}
    local ok, err = validate_entity(config, proxy_cache_schema)
    assert.is_nil(err)
    assert.is_true(ok)
    assert.same(config.content_type, {"text/plain", "application/json"})
  end)

  it("accepts a config with custom values", function()
    local ok, err = validate_entity({
      strategy = "memory",
      response_code = { 200, 301 },
      request_method = { "GET" },
      content_type = { "application/json" },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("accepts an array of numbers as strings", function()
    local ok, err = validate_entity({
      strategy = "memory",
      response_code = {"123", "200"},
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("errors with invalid response_code", function()
    local ok, err = validate_entity({
      strategy = "memory",
      response_code = { 99 },
    }, proxy_cache_schema)

    assert.same("response_code must be an integer within 100 - 999", err.response_code)
    assert.is_false(ok)
  end)

  it("errors if response_code is an empty array", function()
    local ok, err = validate_entity({
      strategy = "memory",
      response_code = {},
    }, proxy_cache_schema)

    assert.same("response_code must contain at least one value", err.response_code)
    assert.is_false(ok)
  end)

  it("errors if response_code is a string", function()
    local ok, err = validate_entity({
      strategy = "memory",
      response_code = "",
    }, proxy_cache_schema)

    assert.same("response_code must contain at least one value", err.response_code)
    assert.is_false(ok)
  end)

  it("errors if response_code has non-numeric values", function()
    local ok, err = validate_entity({
      strategy = "memory",
      response_code = {true, "alo", 123},
    }, proxy_cache_schema)

    assert.same("response_code value must be an integer", err.response_code)
    assert.is_false(ok)
  end)

  it("errors if response_code has float value", function()
    local ok, err = validate_entity({
      strategy = "memory",
      response_code = {123.5},
    }, proxy_cache_schema)

    assert.same("response_code must be an integer within 100 - 999", err.response_code)
    assert.is_false(ok)
  end)



  it("errors with invalid ttl", function()
    local ok, err = validate_entity({
      strategy = "memory",
      cache_ttl = -1
    }, proxy_cache_schema)

    assert.same("cache_ttl must be a positive number", err.cache_ttl)
    assert.is_false(ok)
  end)

  it("accepts a redis config", function()
    local ok, err = validate_entity({
      strategy = "redis",
      redis = {
        host = "127.0.0.1",
        port = 6379,
      },
    }, proxy_cache_schema)

    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("errors with a missing redis config", function()
    local ok, _, err = validate_entity({
      strategy = "redis",
    }, proxy_cache_schema)

    assert.is_false(ok)
    assert.same("No redis config provided", err.message)
  end)

  it("supports vary_query_params values", function()
    local ok, _, err = validate_entity({
      strategy = "memory",
      vary_query_params = "foo",
    }, proxy_cache_schema)

    assert.True(ok)
  end)

  it("supports vary_headers values", function()
    local ok, _, err = validate_entity({
      strategy = "memory",
      vary_headers = "foo",
    }, proxy_cache_schema)

    assert.True(ok)
  end)

  it("sorts vary_query_params values", function()
    local t = {
        strategy = "memory",
        vary_query_params = {"b", "a"}
    }
    local ok, _, err = validate_entity(t, proxy_cache_schema)

    assert.True(ok)
    assert.are.same({"a", "b"}, t.vary_query_params)
    end)

  it("sorts vary_headers values", function()
    local t = {
        strategy = "memory",
        vary_headers = {"b", "A"}
    }
    local ok, _, err = validate_entity(t, proxy_cache_schema)

    assert.True(ok)
    assert.are.same({"a", "b"}, t.vary_headers)
    end)

end)
