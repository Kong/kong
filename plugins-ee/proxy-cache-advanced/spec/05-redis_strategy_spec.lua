-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local cjson = require "cjson"
local redis = require "kong.enterprise_edition.redis"
local redis_strategy = require "kong.plugins.proxy-cache-advanced.strategies.redis"
local utils = require "kong.tools.utils"
local version = require "version"

local REDIS_HOST = helpers.redis_host
local REDIS_PORT = 6379
local REDIS_CLUSTER_ADDRESSES = ee_helpers.redis_cluster_addresses
local REDIS_DATABASE = 1

local REDIS_USERNAME_VALID = "default"
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

  local red_version = string.match(red:info("server"), 'redis_version:([%g]+)\r\n')
  return red, assert(version(red_version))
end

local function add_redis_user(red, red_version)
  if red_version >= version("6.0.0") then
    assert(red:acl("setuser", REDIS_USERNAME_VALID, "on", "allkeys", "allcommands", "allchannels", ">" .. REDIS_PASSWORD_VALID))
    assert(red:save())
  end
end

local function remove_redis_user(red, red_version)
  if red_version >= version("6.0.0") then
    if REDIS_USERNAME_VALID == "default" then
      assert(red:acl("setuser", REDIS_USERNAME_VALID, "nopass"))

    else

      assert(red:acl("deluser", REDIS_USERNAME_VALID))
    end
    assert(red:save())
  end
end

local function redis_test_configurations()
  local redis_configurations = {
    no_auth =  {
      host = REDIS_HOST,
      port = REDIS_PORT,
      database = REDIS_DATABASE,
    },
    single =  {
      host = REDIS_HOST,
      port = REDIS_PORT,
      database = REDIS_DATABASE,
      username = nil,
      password = nil,
    },
    cluster = {
      cluster_addresses = REDIS_CLUSTER_ADDRESSES,
      keepalive_pool_size = 30,
      keepalive_backlog = 30,
      ssl = false,
      ssl_verify = false,
      username = nil,
      password = nil,
    },
  }

  return redis_configurations
end

require"kong.resty.dns.client".init(nil)

for redis_description, redis_configuration in pairs(redis_test_configurations()) do
  describe("proxy-cache-advanced: Redis #" .. redis_description, function()
    local strategy
    local red, red_version

    lazy_setup(function()
      strategy = redis_strategy.new(redis_configuration)
      red, red_version = redis_connect(strategy.conf)

      if red_version >= version("6.0.0") and redis_description ~= "no_auth" then
        add_redis_user(red, red_version)

        strategy.conf.username = REDIS_USERNAME_VALID
        strategy.conf.password = REDIS_PASSWORD_VALID

        red:close()
        red, red_version = redis_connect(strategy.conf)
      end
    end)

    lazy_teardown(function()
      remove_redis_user(red, red_version)
      strategy:flush(true)
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
        local res
        local key = utils.random_string()
        if redis_description ~= "cluster" then
          assert(red:select(REDIS_DATABASE))
        end
        assert(strategy:store(key, cache_obj, 5))

        -- make sure get the cached body
        helpers.wait_until(function()
          res = assert(red:hgetall(key))
          return res and res ~= {}
        end)

        local obj = red:array_to_hash(res)
        obj.headers = cjson.decode(obj.headers)
        obj.timestamp = tonumber(obj.timestamp)
        obj.status = tonumber(obj.status)
        assert.same(obj, cache_obj)
      end)

      it("expires a cache object", function()
        local res
        local key = utils.random_string()
        if redis_description ~= "cluster" then
          assert(red:select(REDIS_DATABASE))
        end
        assert(strategy:store(key, cache_obj, 1))

        -- make sure cached body expires
        helpers.wait_until(function()
          res = assert(red:hgetall(key))
          return next(res) == nil
        end)

        assert.same(res, {})
      end)
    end)

    describe(":fetch [#" .. redis_description .. "]", function()
      it("fetches the same object as stored", function()
        local key = utils.random_string()
        assert(strategy:store(key, cache_obj))
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
        assert(strategy:flush(true))
      end)
    end)
  end)
end
