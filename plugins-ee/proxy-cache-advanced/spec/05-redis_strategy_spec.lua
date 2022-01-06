-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local redis = require "kong.enterprise_edition.redis"
local redis_strategy = require "kong.plugins.proxy-cache-advanced.strategies.redis"
local utils = require "kong.tools.utils"
local version = require "version"

local REDIS_HOST = helpers.redis_host
local REDIS_PORT = 6379
local REDIS_DATABASE = 1

local REDIS_USERNAME_VALID = "rla-user"
local REDIS_PASSWORD_VALID = "rla-pass"

local function redis_connect(conf)
  local red
  if conf then
    red = assert(redis.connection(conf))
  else
    red = assert(redis.connection({
      host = REDIS_HOST,
      port = REDIS_PORT,
    }))
  end
  local red_version = string.match(red:info(), 'redis_version:([%g]+)\r\n')
  return red, assert(version(red_version))
end

local function redis_version(policy)
  local red, red_version = redis_connect()
  red:close()
  return red_version
end

local function add_redis_user(red, red_version)
  local red, red_version = redis_connect()
  if red_version >= version("6.0.0") then
    assert(red:acl("setuser", REDIS_USERNAME_VALID, "on", "allkeys", "+@all", ">" .. REDIS_PASSWORD_VALID))
  end
end

local function remove_redis_user(red, red_version)
  if red_version >= version("6.0.0") then
    assert(red:acl("deluser", REDIS_USERNAME_VALID))
  end
end

local function redis_test_configurations()
  local redis_configurations = {
    no_acl =  {
      host = REDIS_HOST,
      port = REDIS_PORT,
      database = REDIS_DATABASE,
      username = nil,
      password = nil,
    },
  }

  if redis_version() >= version("6.0.0") then
    redis_configurations.acl = {
      host = REDIS_HOST,
      port = REDIS_PORT,
      database = REDIS_DATABASE,
      username = REDIS_USERNAME_VALID,
      password = REDIS_PASSWORD_VALID,
    }
  end

  return redis_configurations
end

require"kong.resty.dns.client".init(nil)

for redis_description, redis_configuration in pairs(redis_test_configurations()) do
  describe("proxy-cache-advanced: Redis strategy", function()
    local strategy
    local red, red_version = redis_connect()

    lazy_setup(function()
      add_redis_user(red, red_version)
      strategy = redis_strategy.new(redis_configuration)
    end)

    lazy_teardown(function()
      redis.flush_redis(REDIS_HOST, REDIS_PORT, REDIS_DATABASE, nil, nil)
      remove_redis_user(red, red_version)
      red:close()
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

    describe(":store [#" .. redis_description .. "]", function()
      it("stores a cache object", function()
        local key = utils.random_string()
        assert(red:select(REDIS_DATABASE))
        assert(strategy:store(key, cache_obj, 2))
        local obj = red:array_to_hash(red:hgetall(key))
        obj.headers = cjson.decode(obj.headers)
        obj.timestamp = tonumber(obj.timestamp)
        obj.status = tonumber(obj.status)
        assert.same(obj, cache_obj)
      end)

      it("expires a cache object", function()
        local key = utils.random_string()
        assert(red:select(REDIS_DATABASE))
        assert(strategy:store(key, cache_obj, 1))
        ngx.sleep(2)
        local obj = red:hgetall(key)
        assert.same(obj, {})
      end)
    end)

    describe(":fetch [#" .. redis_description .. "]", function()
      it("fetches the same object as stored", function()
        local key = utils.random_string()
        assert(strategy:store(key, cache_obj, 5))
        local obj = strategy:fetch(key)
        assert.same(obj, cache_obj)
      end)
    end)

    describe(":purge [#" .. redis_description .. "]", function()
      it("purges a cache entry", function()
        local key = utils.random_string()
        assert(strategy:store(key, cache_obj))
        assert(strategy:purge(key))
        local obj = strategy:fetch(key)
        assert.same(obj, nil)
      end)
    end)

    describe(":touch [#" .. redis_description .. "]", function()
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

    describe(":flush [#" .. redis_description .. "]", function()
      it("returns no error", function()
        assert(strategy:flush())
      end)
    end)
  end)
end
