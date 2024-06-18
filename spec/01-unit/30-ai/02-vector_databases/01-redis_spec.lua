-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local cjson = require("cjson")

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

local fake_redis_url = "redis://localhost:6379"
local default_distance_metric = "EUCLIDEAN"
local default_threshold = 0.3
local test_prefix = "test_prefix"
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

describe("[redis vectordb]", function()
  describe("client:", function()
    it("initializes", function()
      redis_mock.setup(finally)
      local red, err = require("kong.ai.vector_databases.drivers.redis.client").create({ url = fake_redis_url })
      assert.is_nil(err)

      assert.not_nil(red.indexes)
      assert.not_nil(red.cache)
      assert.equal(0, #red.indexes)
      assert.equal(0, #red.cache)
      assert.equal(0, red.key_count)
    end)

    it("fails to initialize if the server connection can't be made", function()
      redis_mock.setup(finally)
      local client = require("kong.ai.vector_databases.drivers.redis.client")
      local redis = require("resty.redis")
      local err_msg = "connection refused"
      redis.forced_failure(err_msg)

      local _, err = client.create({ url = fake_redis_url })
      assert.equal(err_msg, err)

      redis.forced_failure(nil)
    end)
  end)

  describe("indexes:", function()
    it("can manage indexes", function()
      redis_mock.setup(finally)
      local indexes = require("kong.ai.vector_databases.drivers.redis.index")
      local red, err = require("kong.ai.vector_databases.drivers.redis.client").create({ url = fake_redis_url })
      assert.is_nil(err)

      -- creating indexes
      for i = 1, #test_indexes do
        local succeeded, err = indexes.create(red, test_indexes[i], test_prefix, #test_vectors[1],
          default_distance_metric)
        assert.is_nil(err)
        assert.is_true(succeeded)
      end

      -- it should not fail for duplicate indexes
      for i = 1, #test_indexes do
        local succeeded, err = indexes.create(red, test_indexes[i], test_prefix, #test_vectors[1],
          default_distance_metric)
        assert.is_nil(err)
        assert.is_true(succeeded)
      end

      -- deleting indexes
      for i = 1, #test_indexes do
        local succeeded, err = indexes.delete(red, test_indexes[i])
        assert.is_nil(err)
        assert.is_true(succeeded)
      end

      -- can't delete non-existent indexes
      for i = 1, #test_indexes do
        local succeeded, err = indexes.delete(red, test_indexes[i])
        assert.equal("Index not found", err)
        assert.is_false(succeeded)
      end
    end)
  end)

  describe("vectors:", function()
    it("can manage vectors", function()
      redis_mock.setup(finally)
      local indexes = require("kong.ai.vector_databases.drivers.redis.index")
      local vectors = require("kong.ai.vector_databases.drivers.redis.vectors")
      local red, err = require("kong.ai.vector_databases.drivers.redis.client").create({ url = fake_redis_url })
      assert.is_nil(err)

      -- create vectors
      for i = 1, #test_indexes do
        local succeeded, err = vectors.create(red, test_indexes[i], test_vectors[i], test_payloads[i])
        assert.is_nil(err)
        assert.is_true(succeeded)
      end

      -- disallow duplicates
      for i = 1, #test_indexes do
        local succeeded, err = vectors.create(red, test_indexes[i], test_vectors[i], test_payloads[i])
        assert.equal("Already exists", err)
        assert.is_false(succeeded)
      end

      -- fails on non-existent indexes
      local results, err = vectors.search(red, "non_existent_index", test_vectors[1], default_threshold)
      assert.is_nil(results)
      assert.equal("Index not found", err)

      -- search for vectors that have immediate matches
      local succeeded, err = indexes.create(red, test_indexes[1], test_prefix, #test_vectors[1], default_distance_metric)
      assert.is_nil(err)
      assert.is_true(succeeded)
      for i = 1, #test_vectors do
        local results, err = vectors.search(red, test_indexes[1], test_vectors[i], default_threshold)
        assert.is_nil(err)
        assert.equal(default_threshold, red.last_threshold_received)
        assert.is_not_nil(results)
        assert.equal(test_payloads[i], cjson.encode(results))
      end

      -- search for vectors in close proximity
      local vector_known_to_have_another_close_vector = test_vectors_for_search[1]
      local results, err = vectors.search(red, test_indexes[1], vector_known_to_have_another_close_vector,
        default_threshold)
      assert.is_nil(err)
      assert.is_not_nil(results)
      assert.equal(test_payloads[1], cjson.encode(results))

      -- cache miss when there are no vectors in close proximity
      for i = 2, 3 do
        local results, err = vectors.search(red, test_indexes[1], test_vectors_for_search[i], default_threshold)
        assert.is_nil(err)
        assert.is_nil(results)
      end

      -- cache hit for distant vectors if you crank up the threshold
      local crazy_threshold = 500.0
      for i = 2, 3 do
        local results, err = vectors.search(red, test_indexes[1], test_vectors_for_search[i], crazy_threshold)
        assert.is_nil(err)
        assert.is_not_nil(results)
      end
    end)
  end)
end)
