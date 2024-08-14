-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cache            = require("kong.plugins.upstream-oauth.cache")
local helpers          = require "spec.helpers"
local REDIS_HOST       = helpers.redis_host
local REDIS_PORT       = 6379
local REDIS_DATABASE   = 1

local basic_strategies = {
  [cache.constants.STRATEGY_MEMORY] = {
    strategy_name = cache.constants.STRATEGY_MEMORY,
    strategy_opts = {
      dictionary_name = "kong_db_cache"
    }
  },

  [cache.constants.STRATEGY_REDIS] = {
    strategy_name = cache.constants.STRATEGY_REDIS,
    strategy_opts = {
      host = REDIS_HOST,
      port = REDIS_PORT,
      database = REDIS_DATABASE
    }
  }
}

for strategy_name, config in pairs(basic_strategies) do
  describe("upstream-oauth: cache strategies provide a consistent interface (" .. strategy_name .. ")", function()
    it("fetch returns nil if item not in cache", function()
      local strategy = cache.strategy(config)
      local result, err = strategy:fetch("unknown")
      assert.is_nil(result)
      assert.is_nil(err)
    end)

    it("can store and retrieve data", function()
      local strategy = cache.strategy(config)
      local key = "cache-key-store-retrieve"
      local data = "cache-data-store-retrieve"
      local ttl = 1

      local store_result, store_err = strategy:store(key, data, ttl)
      assert.is_true(store_result)
      assert.is_nil(store_err)

      local fetch_result, fetch_err = strategy:fetch(key)
      assert.same(data, fetch_result)
      assert.is_nil(fetch_err)
    end)

    it("can purge data for a given key", function()
      local strategy = cache.strategy(config)
      local key = "cache-key-store-retrieve-purge"
      local data = "cache-data-store-retrieve-purge"
      local ttl = 1

      local store_result, store_err = strategy:store(key, data, ttl)
      assert.is_true(store_result)
      assert.is_nil(store_err)

      local fetch_result, fetch_err = strategy:fetch(key)
      assert.same(data, fetch_result)
      assert.is_nil(fetch_err)

      local purge_result, purge_err = strategy:purge(key)
      assert.is_true(purge_result)
      assert.is_nil(purge_err)

      local result, err = strategy:fetch(key)
      assert.is_nil(result)
      assert.is_nil(err)
    end)

    -- Skip TTL test for memory strategy. This is tested and works under the
    -- the integration tests but expiring keys from nginx shared dictionaries
    -- doesn't work when unit testing.
    if (strategy_name ~= "memory") then
      it("expires data from the cache after the ttl", function()
        local strategy = cache.strategy(config)
        local key = "cache-key-expires"
        local data = "cache-data-expires"
        local ttl = 1

        local store_result, store_err = strategy:store(key, data, ttl)
        assert.is_true(store_result)
        assert.is_nil(store_err)

        helpers.pwait_until(function()
          local fetch_result, fetch_err = strategy:fetch(key)
          assert.is_nil(fetch_result)
          assert.is_nil(fetch_err)
        end)
      end)
    end
  end)
end

describe("upstream-oauth: cache key", function()
  it("creates a key for the cache based on the oauth configuration object", function()
    local conf = {
      token_endpoint = "https://konghq.com/",
      grant_type = "client_credentials",
      scopes = { "openid", "profile" },
      token_post_args = {
        ["test"] = "argument",
        ["custom"] = "argument",
      }
    }
    assert.same(cache.key(conf), cache.key(conf))
  end)

  it("will return the same key if two configuration objects are logically identical", function()
    local conf1 = {
      prim_bool = true,
      prim_num = 1.2345,
      num_arr = { 1, 3, 2, 4 },
      str_arr = { "a", "b", "c", "d", "e" },
      prim_string = "prim_string",
      nested_obj = {
        nested_prim_str = "nested_prim_str",
        nested_prim_num = 5.4321,
        nested_prim_bool = false,
        nested_str_arr = { "z", "y", "x" },
        nested_nil_val = nil,
        nested_num_arr = { 2.2, 3.3, 1.1 },
      }
    }

    local conf2 = {
      prim_string = "prim_string",
      str_arr = { "c", "a", "d", "e", "b" },
      num_arr = { 4, 2, 3, 1 },
      prim_bool = true,
      prim_num = 1.2345,
      nil_val = nil,
      nested_obj = {
        nested_prim_str = "nested_prim_str",
        nested_prim_bool = false,
        nested_prim_num = 5.4321,
        nested_str_arr = { "x", "y", "z" },
        nested_num_arr = { 1.1, 2.2, 3.3 },
        nested_nil_val = nil
      }
    }

    assert.same(cache.key(conf1), cache.key(conf2))
  end)
end)
