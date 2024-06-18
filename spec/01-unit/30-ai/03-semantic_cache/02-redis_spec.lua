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

local redis_vectordb_utils = require("kong.ai.semantic_cache.utils")

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

local driver_name = "redis"
local fake_redis_url = "redis://localhost:6379"
local default_distance_metric = "EUCLIDEAN"
local default_threshold = 0.3
local test_indexes = {
  "test_index1",
  "test_index2",
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

describe("[redis semantic cache]", function()
  describe("driver:", function()
    it("initializes", function()
      redis_mock.setup(finally)
      local driver, err = require("kong.ai.semantic_cache").new({
        driver = driver_name,
        url = fake_redis_url,
        index = test_indexes[1],
        dimensions = #test_vectors[1],
        distance_metric = default_distance_metric,
        default_threshold = default_threshold,
      })
      assert.is_nil(err)

      -- check driver initialization
      assert.is_not_nil(driver)
      assert.equal(driver_name, driver.driver)
      assert.equal(fake_redis_url, driver.url)
      assert.equal(test_indexes[1], driver.index)
      assert.equal(#test_vectors[1], driver.dimensions)
      assert.equal(default_distance_metric, driver.distance_metric)
      assert.equal(default_distance_metric, driver.red.indexes[redis_vectordb_utils.full_index_name(test_indexes[1])])
    end)

    it("fails to initialze a driver without a valid index", function()
      redis_mock.setup(finally)
      local driver, err = require("kong.ai.semantic_cache").new({
        driver = driver_name,
        url = fake_redis_url,
        index = "", -- invalid index
        dimensions = #test_vectors[1],
        distance_metric = default_distance_metric,
        default_threshold = default_threshold,
      })

      -- driver should fail to initialize
      assert.equal("Invalid index name", err)
      assert.is_nil(driver)
    end)



    it("can manage cache", function()
      redis_mock.setup(finally)
      local driver, err = require("kong.ai.semantic_cache").new({
        driver = driver_name,
        url = fake_redis_url,
        index = test_indexes[1],
        dimensions = #test_vectors[1],
        distance_metric = default_distance_metric,
        default_threshold = default_threshold,
      })
      assert.is_nil(err)
      assert.is_not_nil(driver)

      -- insert several cache entries
      for i = 1, #test_vectors do
        local succeeded, err = driver:set_cache(test_vectors[i], test_payloads[i])
        assert.is_nil(err)
        assert.is_true(succeeded)
      end
      assert.equal(3, driver.red.key_count)

      -- should tolerate redundant cache entries
      for i = 1, #test_vectors do
        local succeeded, err = driver:set_cache(test_vectors[i], test_payloads[i])
        assert.is_nil(err)
        assert.is_true(succeeded)
      end
      assert.equal(6, driver.red.key_count)

      -- should use the default threshold for cache searches when not otherwise prompted
      assert.equal(0.0, driver.red.last_threshold_received)
      for i = 1, #test_vectors do
        local results, err = driver:get_cache(test_vectors[i])
        assert.is_nil(err)
        assert.equal(default_threshold, driver.red.last_threshold_received)
        assert.is_not_nil(results)
        assert.equal(test_payloads[i], cjson.encode(results))
      end

      -- allows a threshold override
      local threshold = 0.1
      assert.equal(default_threshold, driver.red.last_threshold_received)
      for i = 1, #test_vectors do
        local results, err = driver:get_cache(test_vectors[i], threshold)
        assert.is_nil(err)
        assert.equal(threshold, driver.red.last_threshold_received)
        assert.is_not_nil(results)
        assert.equal(test_payloads[i], cjson.encode(results))
      end

      -- can search and find a close proximity vector when there's no direct match
      local vector_known_to_have_another_close_vector = test_vectors_for_search[1]
      local results, err = driver:get_cache(vector_known_to_have_another_close_vector)
      assert.is_nil(err)
      assert.is_not_nil(results)
      assert.equal(test_payloads[1], cjson.encode(results))

      -- will receive a cache miss for vector searches where no other vectors are even close
      for i = 2, 3 do
        local results, err = driver:get_cache(test_vectors_for_search[i])
        assert.is_nil(err)
        assert.is_nil(results)
      end

      -- will receive a cache hit for very distant vectors if you crank up the threshold
      local crazy_threshold = 500.0
      for i = 2, 3 do
        local results, err = driver:get_cache(test_vectors_for_search[i], crazy_threshold)
        assert.is_nil(err)
        assert.is_not_nil(results)
      end

      -- will return an error if there are connection issues
      local redis = require("resty.redis")
      local err_msg = "connection refused"
      redis.forced_failure(err_msg)

      for i = 1, #test_vectors do
        local succeeded, err = driver:set_cache(test_vectors[i], test_payloads[i])
        assert.equal(err_msg, err)
        assert.is_false(succeeded)
      end

      for i = 1, #test_vectors do
        local results, err = driver:get_cache(test_vectors[i])
        assert.is_nil(results)
        assert.equal(err_msg, err)
      end

      redis.forced_failure(nil)
    end)
  end)
end)
