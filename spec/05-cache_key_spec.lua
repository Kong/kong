local utils = require "kong.tools.utils"
local key_utils = require "kong.plugins.proxy-cache.cache_key"


describe("prefix_uuid", function()
  local consumer1_uuid = utils.uuid()
  local consumer2_uuid = utils.uuid()
  local route1_uuid = utils.uuid()
  local route2_uuid = utils.uuid()
  local api1_uuid = utils.uuid()
  local api2_uuid = utils.uuid()

  it("returns distinct prefixes for a consumer on different apis", function()
    local prefix1 = assert(key_utils.prefix_uuid(consumer1_uuid, api1_uuid,
      nil))
    local prefix2 = assert(key_utils.prefix_uuid(consumer1_uuid, api2_uuid,
      nil))

    assert.not_equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
    assert.not_equal("default", prefix2)
  end)

  it("returns distinct prefixes for different consumers on an api", function()
    local prefix1 = assert(key_utils.prefix_uuid(consumer1_uuid, api1_uuid,
                           route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(consumer2_uuid, api1_uuid,
                           route2_uuid))

    assert.not_equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
    assert.not_equal("default", prefix2)
  end)

  it("returns distinct prefixes for a consumer on different routes", function()
    local prefix1 = assert(key_utils.prefix_uuid(consumer1_uuid, nil,
      route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(consumer1_uuid, nil,
      route2_uuid))

    assert.not_equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
    assert.not_equal("default", prefix2)
  end)

  it("returns distinct prefixes for different consumers on a route", function()
    local prefix1 = assert(key_utils.prefix_uuid(consumer1_uuid, nil,
      route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(consumer2_uuid, nil,
      route1_uuid))

    assert.not_equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
    assert.not_equal("default", prefix2)
  end)

  it("returns the same prefix for an api with no consumer", function()
    local prefix1 = assert(key_utils.prefix_uuid(nil, api1_uuid, nil))
    local prefix2 = assert(key_utils.prefix_uuid(nil, api1_uuid, nil))

    assert.equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
  end)

  it("returns the same prefix for a route with no consumer", function()
    local prefix1 = assert(key_utils.prefix_uuid(nil, nil, route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(nil, nil, route1_uuid))

    assert.equal(prefix1, prefix2)
    assert.not_equal("default", prefix1)
  end)

  it("returns a consumer-specific prefix for apis", function()
    local prefix1 = assert(key_utils.prefix_uuid(nil, api1_uuid, nil))
    local prefix2 = assert(key_utils.prefix_uuid(consumer1_uuid, api1_uuid, nil))

    assert.not_equal(prefix1, prefix2)
  end)

  it("returns a consumer-specific prefix for routes", function()
    local prefix1 = assert(key_utils.prefix_uuid(nil, nil, route1_uuid))
    local prefix2 = assert(key_utils.prefix_uuid(consumer1_uuid, nil, route1_uuid))

    assert.not_equal(prefix1, prefix2)
  end)

  describe("returns 'default' if", function()
    it("no consumer_id, api_id, or route_id was given", function()
      assert.equal("default", key_utils.prefix_uuid(nil, nil, nil))
    end)
    it("only consumer_id was given", function()
      assert.equal("default", key_utils.prefix_uuid(consumer1_uuid, nil, nil))
    end)
  end)

  describe("does not return 'default' if", function()
    it("api_id is non-nil", function()
      assert.not_equal("default", key_utils.prefix_uuid(nil, api1_uuid, nil))
    end)
    it("route_id is non-nil", function()
      assert.not_equal("default", key_utils.prefix_uuid(nil, route1_uuid, nil))
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
      local s1 = "a" .. utils.random_string()
      local s2 = "b" .. utils.random_string()
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
      local s1 = "a" .. utils.random_string()
      local s2 = "b" .. utils.random_string()
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
