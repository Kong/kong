local key_utils = require "kong.plugins.proxy-cache.cache_key"
local random_string = require("kong.tools.rand").random_string
local uuid = require("kong.tools.uuid").uuid


describe("prefix_uuid", function()
  local consumer1_uuid = uuid()
  local consumer2_uuid = uuid()
  local route1_uuid = uuid()
  local route2_uuid = uuid()

  it("returns distinct prefixes for a consumer on different routes", function()
    local prefix1 = assert(key_utils.prefix_uuid(consumer1_uuid, route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(consumer1_uuid, route2_uuid))

    assert.not_equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
    assert.not_equal("default", prefix2)
  end)

  it("returns distinct prefixes for different consumers on a route", function()
    local prefix1 = assert(key_utils.prefix_uuid(consumer1_uuid, route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(consumer2_uuid, route1_uuid))

    assert.not_equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
    assert.not_equal("default", prefix2)
  end)

  it("returns the same prefix for a route with no consumer", function()
    local prefix1 = assert(key_utils.prefix_uuid(nil, route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(nil, route1_uuid))

    assert.equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
  end)

  it("returns a consumer-specific prefix for routes", function()
    local prefix1 = assert(key_utils.prefix_uuid(nil, route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(consumer1_uuid, route1_uuid))

    assert.not_equal(prefix1, prefix2)
  end)

  describe("returns 'default' if", function()
    it("no consumer_id, api_id, or route_id was given", function()
      assert.equal("default", key_utils.prefix_uuid())
    end)
    it("only consumer_id was given", function()
      assert.equal("default", key_utils.prefix_uuid(consumer1_uuid))
    end)
  end)

  describe("does not return 'default' if", function()
    it("route_id is non-nil", function()
      assert.not_equal("default", key_utils.prefix_uuid(nil, route1_uuid))
    end)
  end)
end)

describe("params_key", function()
  it("defaults to all", function()
    assert.equal("a=1:b=2", key_utils.params_key({a = 1, b = 2},{}))
  end)

  it("empty query_string returns empty", function()
    assert.equal("", key_utils.params_key({},{}))
  end)

  it("empty query_string returns empty with vary query_params", function()
    assert.equal("", key_utils.params_key({},{"a"}))
  end)

  it("sorts the arguments", function()
    for i = 1, 100 do
      local s1 = "a" .. random_string()
      local s2 = "b" .. random_string()
      assert.equal(s1.."=1:".. s2 .. "=2", key_utils.params_key({[s2] = 2, [s1] = 1},{}))
    end
  end)

  it("uses only params specified in vary", function()
    assert.equal("a=1", key_utils.params_key({a = 1, b = 2},
                   {vary_query_params = {"a"}}))
  end)

  it("deals with multiple params with same name", function()
    assert.equal("a=1,2", key_utils.params_key({a = {1, 2}},
                   {vary_query_params = {"a"}}))
    end)

  it("deals with multiple params with same name and sorts", function()
    assert.equal("a=1,2", key_utils.params_key({a = {2, 1}},
                   {vary_query_params = {"a"}}))
    end)

  it("discards params in config that are not in the request", function()
    assert.equal("a=1,2:b=2", key_utils.params_key({a = {1, 2}, b = 2},
                   {vary_query_params = {"a", "b", "c"}}))
    end)
end)

describe("headers_key", function()
  it("defaults to none", function()
    assert.equal("", key_utils.headers_key({a = 1, b = 2},{}))
  end)

  it("sorts the arguments", function()
    for i = 1, 100 do
      local s1 = "a" .. random_string()
      local s2 = "b" .. random_string()
      assert.equal(s1.."=1:".. s2 .. "=2", key_utils.params_key({[s2] = 2, [s1] = 1},
                     {vary_headers = {"a", "b"}}))
    end
  end)

  it("uses only params specified in vary", function()
    assert.equal("a=1", key_utils.headers_key({a = 1, b = 2},
                   {vary_headers = {"a"}}))
  end)

  it("deals with multiple params with same name", function()
    assert.equal("a=1,2", key_utils.headers_key({a = {1, 2}},
                   {vary_headers = {"a"}}))
    end)

  it("deals with multiple params with same name and sorts", function()
    assert.equal("a=1,2", key_utils.headers_key({a = {2, 1}},
                   {vary_headers = {"a"}}))
    end)

  it("discards params in config that are not in the request", function()
    assert.equal("a=1,2:b=2", key_utils.headers_key({a = {1, 2}, b = 2},
                   {vary_headers = {"a", "b", "c"}}))
  end)
end)

describe("normalize_accept_encoding", function()
  it("returns 'none' for nil header", function()
    assert.equal("none", key_utils.normalize_accept_encoding(nil))
  end)

  it("returns 'none' for empty string", function()
    assert.equal("none", key_utils.normalize_accept_encoding(""))
  end)

  it("returns 'none' for whitespace only", function()
    assert.equal("none", key_utils.normalize_accept_encoding("   "))
  end)

  it("handles single encoding", function()
    assert.equal("gzip", key_utils.normalize_accept_encoding("gzip"))
  end)

  it("handles single encoding with whitespace", function()
    assert.equal("gzip", key_utils.normalize_accept_encoding("  gzip  "))
  end)

  it("handles multiple encodings", function()
    local result = key_utils.normalize_accept_encoding("gzip, deflate, br")
    -- encodings should be sorted
    assert.equal("br,deflate,gzip", result)
  end)

  it("handles multiple encodings with different order", function()
    local result1 = key_utils.normalize_accept_encoding("gzip, deflate, br")
    local result2 = key_utils.normalize_accept_encoding("br, gzip, deflate")
    -- should normalize to same value
    assert.equal(result1, result2)
  end)

  it("handles case insensitivity", function()
    assert.equal("gzip", key_utils.normalize_accept_encoding("GZIP"))
    assert.equal("gzip", key_utils.normalize_accept_encoding("Gzip"))
    assert.equal("gzip", key_utils.normalize_accept_encoding("gZiP"))
  end)

  it("handles quality values", function()
    local result = key_utils.normalize_accept_encoding("gzip;q=1.0, deflate;q=0.8")
    -- quality values should be stripped, encodings sorted
    assert.equal("deflate,gzip", result)
  end)

  it("handles complex quality values with whitespace", function()
    local result = key_utils.normalize_accept_encoding("gzip ; q=1.0 , deflate ; q=0.8")
    assert.equal("deflate,gzip", result)
  end)

  it("ignores wildcard encoding", function()
    assert.equal("gzip", key_utils.normalize_accept_encoding("gzip, *"))
  end)

  it("handles identity encoding", function()
    assert.equal("identity", key_utils.normalize_accept_encoding("identity"))
  end)

  it("handles multiple encodings with mixed case and quality", function()
    local result = key_utils.normalize_accept_encoding("GZIP;q=1.0, Deflate;q=0.8, BR")
    assert.equal("br,deflate,gzip", result)
  end)

  it("handles real-world browser Accept-Encoding header", function()
    local result = key_utils.normalize_accept_encoding("gzip, deflate, br")
    assert.equal("br,deflate,gzip", result)
  end)

  it("returns consistent results for equivalent headers", function()
    local headers = {
      "gzip, deflate",
      "deflate, gzip",
      "gzip;q=1.0, deflate;q=1.0",
      "GZIP, DEFLATE",
      "  gzip  ,  deflate  ",
    }

    local first_result = key_utils.normalize_accept_encoding(headers[1])
    for i = 2, #headers do
      local result = key_utils.normalize_accept_encoding(headers[i])
      assert.equal(first_result, result,
        "Expected '" .. headers[i] .. "' to normalize to same value as '" .. headers[1] .. "'")
    end
  end)
end)
