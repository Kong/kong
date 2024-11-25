-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local uuid = require "kong.tools.uuid".uuid
local redis_mock = require("spec.helpers.ai.redis_mock")

--
-- test setup
--

-- initialize kong.global (so logging works, e.t.c.)
local kong_global = require "kong.global"
_G.kong = kong_global.new()
kong_global.init_pdk(kong, nil)

--
-- test data
--

local default_distance_metric = "euclidean"
local default_threshold = 0.3
local test_indexes = {
  "test_index1",
  "test_index2",
  "test_index3",
}
local test_vectors = {
  { 1.0, 1.1,  -1.1, 3.4 },
  { 1.1, 1.2,  -1.1, -0.5 },
  { 5.6, -5.5, -1.6, -0.2 },
}
local test_vectors_for_search = {
  { 1.1,   1.2,  -1.0,  3.4 },    -- is in close proximity to test_vectors[1] (threshold 0.3 will hit)
  { 100.6, 88.4, -20.5, -5.5 },   -- no close proximity (threshold 0.3 will miss, but 500.0 will hit)
  { 99.6,  42.0, -10.5, -128.9 }, -- no close proximity (threshold 0.3 will miss, but 500.0 will hit)
}
local test_payloads = {
  [[{"message":"test_payload1"}]],
  [[{"message":"test_payload2"}]],
  [[{"message":"test_payload3"}]],
}

--
-- tests
--


local default_config = {
  distance_metric = default_distance_metric,
  threshold = default_threshold,
  dimensions = 4,
  redis = {},
}

local default_namespace = "kong"

describe("[redis vectordb]", function()

  after_each(function()
    redis_mock.clear()
  end)

  describe("client:", function()
    it("initializes", function()
      redis_mock.setup(finally)
      local client, err = require("kong.llm.vectordb.strategies.redis").new(default_namespace, default_config)
      assert.is_nil(err)
      assert.truthy(client)
    end)

    it("fails to initialize if the server connection can't be made", function()
      redis_mock.setup(finally)
      local mod = require("kong.llm.vectordb.strategies.redis")
      local redis = require("resty.redis.connector")
      local err_msg = "connection refused"
      redis.forced_failure(err_msg)

      local _, err = mod.new(default_namespace, default_config)
      assert.equal(err_msg, err)

      redis.forced_failure(nil)
    end)
  end)

  describe("indexes:", function()
    it("can manage indexes", function()
      redis_mock.setup(finally)
      local mod = require("kong.llm.vectordb.strategies.redis")

      -- creating indexes
      for i = 1, #test_indexes do
        local succeeded, err = mod.new(test_indexes[i], {
          dimensions = #test_vectors[1],
          distance_metric = default_distance_metric
        })
        assert.is_nil(err)
        assert.truthy(succeeded)
      end

      -- it should not fail for duplicate indexes
      for i = 1, #test_indexes do
        local succeeded, err = mod.new(test_indexes[i], {
          dimensions = #test_vectors[1],
          distance_metric = default_distance_metric
        })
        assert.is_nil(err)
        assert.truthy(succeeded)
      end
    end)
  end)

  describe("vectors:", function()
    it("insert", function()
      redis_mock.setup(finally)
      local mod = require("kong.llm.vectordb.strategies.redis")

      -- create vectors
      for i = 1, #test_indexes do
        local client, err = mod.new(test_indexes[i], {
          dimensions = #test_vectors[1],
          distance_metric = default_distance_metric,
        })
        assert.is_nil(err)
        assert.truthy(client)
        local key, err = client:insert(test_vectors[i], test_payloads[i], i)
        assert.is_nil(err)
        assert.truthy(key)
      end

    end)

    it("insert, set and get ttl", function()
      redis_mock.setup(finally)
      local mod = require("kong.llm.vectordb.strategies.redis")

      local client, err = mod.new(test_indexes[1], {
        dimensions = #test_vectors[1],
        distance_metric = default_distance_metric,
      })
      assert.is_nil(err)
      assert.truthy(client)
      local key, err = client:insert(test_vectors[1], test_payloads[1], "1", 100)
      assert.is_nil(err)
      assert.truthy(key)

      ngx.sleep(1)

      local out = {}
      local value, err = client:get(key, out)
      assert.is_nil(err)
      assert.same(test_payloads[1], value)
      assert.truthy(out.ttl > 0)
      assert.truthy(out.ttl <= 100)

      local key, err = client:set("mykey", test_payloads[1], 100)
      assert.is_nil(err)
      assert.truthy(key)

      local out = {}
      local value, err = client:get("mykey", out)
      assert.is_nil(err)
      assert.same(test_payloads[1], value)
      assert.truthy(out.ttl > 0)
      assert.truthy(out.ttl <= 100)
    end)

    it("delete", function()
      redis_mock.setup(finally)
      local mod = require("kong.llm.vectordb.strategies.redis")

      local client, err = mod.new(test_indexes[1], {
        dimensions = #test_vectors[1],
        distance_metric = default_distance_metric,
      })
      assert.is_nil(err)
      assert.truthy(client)
      local key, err = client:insert(test_vectors[1], test_payloads[1], uuid())
      assert.is_nil(err)
      assert.truthy(key)
      local ok, err = client:delete(key)
      assert.is_nil(err)
      assert.truthy(ok)

      local red2 = assert(require("kong.enterprise_edition.tools.redis.v2").connection(default_config.redis))
      local res, err = red2["JSON.GET"](red2, key)
      assert.truthy(res == nil)
      assert.is_nil(err)
    end)

    it("search", function()
      redis_mock.setup(finally)
      local mod = require("kong.llm.vectordb.strategies.redis")

      -- search for vectors that have immediate matches
      local clients = {}
      local out = {}
      for i = 1, #test_vectors do
        local client, err = mod.new(test_indexes[i], {
          dimensions = #test_vectors[i],
          distance_metric = default_distance_metric,
        })
        assert.is_nil(err)
        assert.truthy(client)
        local key, err = client:insert(test_vectors[i], test_payloads[i], i)
        assert.is_nil(err)
        assert.truthy(key)

        clients[i] = client

        local results, err = client:search(test_vectors[i], default_threshold, out)
        assert.is_nil(err)
        -- in the mock we put the distance as the score
        assert.is_not_nil(results)
        assert.not_nil(out.score)
        assert.same(test_payloads[i], results)
      end

      -- search for vectors in close proximity
      local vector_known_to_have_another_close_vector = test_vectors_for_search[1]
      local results, err = clients[1]:search(vector_known_to_have_another_close_vector,
        default_threshold)
      assert.is_nil(err)
      assert.is_not_nil(results)
      assert.same(test_payloads[1], results)

      -- cache miss when there are no vectors in close proximity
      for i = 2, 3 do
        local results, err = clients[1]:search(test_vectors_for_search[i], default_threshold)
        assert.is_nil(err)
        assert.is_nil(results)
      end

      -- cache hit for distant vectors if you crank up the threshold
      local crazy_threshold = 500.0
      for i = 2, 3 do
        local results, err = clients[1]:search(test_vectors_for_search[i], crazy_threshold)
        assert.is_nil(err)
        assert.is_not_nil(results)
      end
    end)
  end)
end)
