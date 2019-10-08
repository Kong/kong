local redis = require "resty.redis"
local redis_strategy = require "kong.plugins.proxy-cache-advanced.strategies.redis"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local helpers = require "spec.helpers"

require"resty.dns.client".init(nil)

local REDIS_DB = 1

describe("proxy-cache-advanced: Redis strategy", function()
  local strategy, redis_client

  local redis_config = {
    host = helpers.redis_host,
    port = 6379,
    database = REDIS_DB,
  }

  setup(function()
    strategy = redis_strategy.new(redis_config)
    redis_client = redis:new()
    redis_client:connect(redis_config.host, redis_config.port)
  end)

  teardown(function()
    redis_client:flushall()
  end)

  local cache_obj = {
    headers = {
      ["a-header"] = "a-header-value",
      ["another-header"] = "another-header-value",
    },
    status = 200,
    body = "a body",
    timestamp = ngx.time(),
  }

  describe(":store", function()
    it("stores a cache object", function()
      local key = utils.random_string()
      assert(redis_client:select(REDIS_DB))
      assert(strategy:store(key, cache_obj, 2))
      local obj = redis_client:array_to_hash(redis_client:hgetall(key))
      obj.headers = cjson.decode(obj.headers)
      obj.timestamp = tonumber(obj.timestamp)
      obj.status = tonumber(obj.status)
      assert.same(obj, cache_obj)
    end)

    it("expires a cache object", function()
      local key = utils.random_string()
      assert(redis_client:select(REDIS_DB))
      assert(strategy:store(key, cache_obj, 1))
      ngx.sleep(2)
      local obj = redis_client:hgetall(key)
      assert.same(obj, {})
    end)
  end)

  describe(":fetch", function()
    it("fetches the same object as stored", function()
      local key = utils.random_string()
      assert(strategy:store(key, cache_obj, 5))
      local obj = strategy:fetch(key)
      assert.same(obj, cache_obj)
    end)
  end)

  describe(":purge", function()
    it("purges a cache entry", function()
      local key = utils.random_string()
      assert(strategy:store(key, cache_obj))
      assert(strategy:purge(key))
      local obj = strategy:fetch(key)
      assert.same(obj, nil)
    end)
  end)

  describe(":touch", function()
    it("updates cached entry timestamp field", function()
      local key = utils.random_string()
      local ts = cache_obj.timestamp
      assert(strategy:store(key, cache_obj))
      local obj = strategy:fetch(key)
      assert.same(obj.timestamp, ts)
      assert(strategy:touch(key))
      local obj = strategy:fetch(key)
      assert.not_same(obj.timestamp, ts)
    end)
  end)

  describe(":flush", function()
    it("returns no error", function()
      assert(strategy:flush())
    end)
  end)
end)
