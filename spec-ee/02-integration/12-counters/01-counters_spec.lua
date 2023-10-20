-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local time = ngx.time
local cjson = require "cjson.safe"

local helpers = require "spec.helpers"
local kong_counters = require "kong.enterprise_edition.counters"

local FLUSH_LIST_KEY = "counters:flush_list"
local FLUSH_LOCK_KEY = "counters:flush_lock"

for _, strategy in helpers.each_strategy() do
  describe("counters with db: #" .. strategy, function()
    local snapshot,
          counters

    setup(function()
      counters = kong_counters.new({})
    end)

    before_each(function()
      counters.counters.metrics = {}
      counters.list_cache:delete(FLUSH_LOCK_KEY .. ":" .. counters.name)
      snapshot = assert:snapshot()
    end)

    after_each(function()
      snapshot:revert()
    end)

    teardown(function()
      counters.counters.metrics = {}
      counters.list_cache:delete(FLUSH_LOCK_KEY .. ":" .. counters.name)

      local v = ngx.shared.kong_counters:get(FLUSH_LOCK_KEY .. ":" .. counters.name)
      assert.is_nil(v)
    end)

    describe("new()", function()
      it("should be configured with default settings", function()
        assert.truthy(counters.node_id)
        assert.truthy(counters.name)
        assert.equals(#counters.name, 45)
        assert.equals(counters.flush_interval, 15)
        assert.truthy(counters.counters)
        assert.truthy(counters.counters.start_at)
        assert.truthy(counters.counters.metrics)
      end)
    end)

    describe("flush_lock()", function()
      it("should acquire lock for first attempt and fail for the second", function()
        local lock, err = counters:flush_lock()
        assert.is_true(lock)
        assert.is_nil(err)

        local lock, err = counters:flush_lock()
        assert.is_false(lock)
        assert.is_nil(err)
      end)
    end)

    describe("current_bucket()", function()
      it("should retrieve current bucket name as 1 after 1 second passed", function()
        counters.counters.start_at = time() - 1

        local current_bucket = counters:current_bucket()
        assert.equals('1', current_bucket)
      end)

      it("should retrieve current bucket name as 14 after 14 second passed", function()
        counters.counters.start_at = time() - 14

        local current_bucket = counters:current_bucket()
        assert.equals('14', current_bucket)
      end)
    end)

    describe("add_key()", function()
      it("should add `test` key to counters object", function()
        counters:add_key("test")
        assert.truthy(counters.counters.metrics.test)
      end)

      it("should add `foo` and `bar` keys to counters object", function()
        counters:add_key("foo")
        counters:add_key("bar")
        assert.truthy(counters.counters.metrics.foo)
        assert.truthy(counters.counters.metrics.bar)
      end)
    end)

    describe("increment()", function()
      it("should increment key `foo` by 2", function()
        local KEY_NAME = "foo"

        counters:add_key(KEY_NAME)
        counters:increment(KEY_NAME)
        counters:increment(KEY_NAME)

        local total = 0
        if counters.counters.metrics[KEY_NAME] then
          for _, val in pairs(counters.counters.metrics[KEY_NAME]) do
            total = total + val
          end
        end

        assert.equals(2, total)
      end)

      it("should fail to increment none existing key", function()
        local KEY_NAME = "none"

        counters:increment(KEY_NAME)
        counters:increment(KEY_NAME)

        local total = 0
        if counters.counters.metrics[KEY_NAME] then
          for _, val in pairs(counters.counters.metrics[KEY_NAME]) do
            total = total + val
          end
        end
        assert.equals(0, total)
      end)
    end)

    describe("reset_counters()", function()
      it("should reset counters data with one key", function()
        local KEY_NAME = "foo"

        counters:add_key(KEY_NAME)
        counters:increment(KEY_NAME)
        counters:increment(KEY_NAME)

        local total = 0
        if counters.counters.metrics[KEY_NAME] then
          for _, val in pairs(counters.counters.metrics[KEY_NAME]) do
            total = total + val
          end
        end

        assert.equals(2, total)

        counters:reset_counters()

        total = 0
        if counters.counters.metrics[KEY_NAME] then
          for _, val in pairs(counters.counters.metrics[KEY_NAME]) do
            total = total + val
          end
        end

        assert.equals(0, total)
      end)

      it("should reset counters data with multiple keys", function()
        local KEY_FOO = "foo"
        local KEY_BAR = "bar"

        counters:add_key(KEY_FOO)
        counters:increment(KEY_FOO)
        counters:increment(KEY_FOO)
        counters:increment(KEY_FOO)

        counters:add_key(KEY_BAR)
        counters:increment(KEY_BAR)

        local total = 0
        for _, val in pairs(counters.counters.metrics[KEY_FOO]) do
          total = total + val
        end

        for _, val in pairs(counters.counters.metrics[KEY_BAR]) do
          total = total + val
        end

        assert.equals(4, total)

        counters:reset_counters()

        total = 0
        for _, val in pairs(counters.counters.metrics[KEY_FOO]) do
          total = total + val
        end

        for _, val in pairs(counters.counters.metrics[KEY_BAR]) do
          total = total + val
        end

        assert.equals(0, total)
      end)

      it("should reset counters data, remain keys and set different start_at", function()
        local KEY_FOO = "foo"
        local KEY_BAR = "bar"

        ngx.update_time()
        counters:add_key(KEY_FOO)
        counters:add_key(KEY_BAR)

        -- sleep a bit to get a new value set to start_at variable
        ngx.sleep(1)

        local start_at_1 = counters.counters.start_at
        counters:reset_counters()
        local start_at_2 = counters.counters.start_at
        assert.not_equal(start_at_1, start_at_2)

        assert.truthy(counters.counters.metrics[KEY_FOO])
        assert.truthy(counters.counters.metrics[KEY_BAR])

        assert.falsy(counters.counters.metrics["empty"])
      end)
    end)

    -- pending until we can mock out list shm functions
    pending("merge_worker_data()", function()
      it("should merge data from 3 workers", function()
        local flush_key = FLUSH_LIST_KEY .. ":" .. counters.name
        -- to imitate data that workers pushed we will add data straight to the cache
        local KEY_KEY1 = "key_1"
        local KEY_KEY2 = "key_2"

        counters:add_key(KEY_KEY1)
        counters:add_key(KEY_KEY2)

        counters:increment(KEY_KEY1)
        counters:increment(KEY_KEY1)
        counters:increment(KEY_KEY1)

        counters:increment(KEY_KEY2)
        counters:increment(KEY_KEY2)
        counters:increment(KEY_KEY2)
        counters:increment(KEY_KEY2)

        local worker_1_data = counters.counters.metrics

        -- encode and push worker 1 data
        local data = cjson.encode(worker_1_data)
        counters.list_cache:rpush(flush_key, data)
        counters:reset_counters()

        counters:increment(KEY_KEY1)
        counters:increment(KEY_KEY2)

        local worker_2_data = counters.counters.metrics

        -- encode and push worker 2 data
        data = cjson.encode(worker_2_data)
        counters.list_cache:rpush(flush_key, data)

        counters:merge_worker_data(flush_key)
      end)
    end)
  end)
end
