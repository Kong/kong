-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.tools.utils"
local key_utils = require "kong.plugins.proxy-cache-advanced.cache_key"


describe("prefix_uuid", function()
  local consumer1_uuid = utils.uuid()
  local consumer2_uuid = utils.uuid()
  local route1_uuid = utils.uuid()
  local route2_uuid = utils.uuid()

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

describe("build_cache_key", function()
  it("creates different cache_keys when no group is present", function()
    local cache_key_with_group = key_utils.build_cache_key("alice",
      nil, nil, nil, {}, {}, { name = "my-group", id = 1 }, {})

    local cache_key_no_group = key_utils.build_cache_key("alice",
      nil, nil, nil, {}, {}, {}, {})
    assert.is_not_equal(cache_key_with_group, cache_key_no_group)
  end)
  it("creates same cache_keys when same parameters are passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group1", id = 2 }, {})
    local cache_key2 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group1", id = 2 }, {})
    assert.is_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different users are passed", function()
    local cache_key1 = key_utils.build_cache_key("alice", "1", nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    local cache_key2 = key_utils.build_cache_key("bob", "1", nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different groups are passed", function()
    local cache_key1 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    local cache_key2 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group2", id = 2 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different parameters are passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", nil, nil, nil, { param1 = "value1" }, {},
      { name = "group1", id = 2 }, {})
    local cache_key2 = key_utils.build_cache_key("bob", nil, nil, nil, { param1 = "value2" }, {},
      { name = "group1", id = 2 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates same cache_keys when different headers are passed but no vary option is passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", "1", nil, nil, {}, { header1 = "value1" },
      { name = "group1", id = 2 }, {})
    local cache_key2 = key_utils.build_cache_key("bob", "1", nil, nil, {}, { header1 = "value2" },
      { name = "group1", id = 2 }, {})
    assert.is_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different groups with same name but different ids are passed", function()
    local cache_key1 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    local cache_key2 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group1", id = 2 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different URIs are passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", "uri1", nil, nil, {}, {}, { name = "group1", id = 2 }, {})
    local cache_key2 = key_utils.build_cache_key("bob", "uri2", nil, nil, {}, {}, { name = "group1", id = 2 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different methods are passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", nil, "GET", nil, {}, {}, { name = "group1", id = 2 }, {})
    local cache_key2 = key_utils.build_cache_key("bob", nil, "POST", nil, {}, {}, { name = "group1", id = 2 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different uris are passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", nil, nil, "uri1", {}, {}, { name = "group1", id = 2 },
      {})
    local cache_key2 = key_utils.build_cache_key("bob", nil, nil, "uri2", {}, {}, { name = "group1", id = 2 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different groups with different names but same ids are passed", function()
    local cache_key1 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    local cache_key2 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group2", id = 1 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates same cache_keys when same query parameters are passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group1", id = 2 },
      { query1 = "value1" })
    local cache_key2 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group1", id = 2 },
      { query1 = "value1" })
    assert.is_equal(cache_key1, cache_key2)
  end)

  it("creates same cache_keys when same body parameters are passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group1", id = 2 }, {},
      { body1 = "value1" })
    local cache_key2 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group1", id = 2 }, {},
      { body1 = "value1" })
    assert.is_equal(cache_key1, cache_key2)
  end)

  it("creates same cache_keys when same cookies are passed", function()
    local cache_key1 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group1", id = 2 }, {}, {},
      { cookie1 = "value1" })
    local cache_key2 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group1", id = 2 }, {}, {},
      { cookie1 = "value1" })
    assert.is_equal(cache_key1, cache_key2)
  end)

  it("creates same cache_keys when same groups with different names but same ids are passed", function()
    local cache_key1 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    local cache_key2 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group2", id = 1 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates different cache_keys when different users and different groups are passed", function()
    local cache_key1 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    local cache_key2 = key_utils.build_cache_key("bob", nil, nil, nil, {}, {}, { name = "group2", id = 2 }, {})
    assert.is_not_equal(cache_key1, cache_key2)
  end)

  it("creates same cache_keys when same users and same groups are passed", function()
    local cache_key1 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    local cache_key2 = key_utils.build_cache_key("alice", nil, nil, nil, {}, {}, { name = "group1", id = 1 }, {})
    assert.is_equal(cache_key1, cache_key2)
  end)
end)
