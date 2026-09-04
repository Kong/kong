local redis_helper = require "spec.helpers.redis_helper"
local helpers = require "spec.helpers"

local REDIS_HOST = helpers.redis_host
local REDIS_PORT = helpers.redis_port
local REDIS_DATABASE1 = 1
local REDIS_DATABASE2 = 2

describe("redis_helper tests", function()
  describe("connect", function ()
    describe("when connection info is correct", function()
      it("connects to redis", function()
        local red, version = redis_helper.connect(REDIS_HOST, REDIS_PORT)
        assert.is_truthy(version)
        assert.is_not_nil(red)
      end)
    end)

    describe("when connection info is invalid", function ()
      it("does not connect to redis", function()
        assert.has_error(function()
          redis_helper.connect(REDIS_HOST, 5123)
        end)
      end)
    end)
  end)

  describe("reset_redis", function ()
    it("clears redis database", function()
      -- given - redis with some values in 2 databases
      local red = redis_helper.connect(REDIS_HOST, REDIS_PORT)
      red:select(REDIS_DATABASE1)
      red:set("dog", "an animal")
      local ok, err = red:get("dog")
      assert.falsy(err)
      assert.same("an animal", ok)

      red:select(REDIS_DATABASE2)
      red:set("cat", "also animal")
      local ok, err = red:get("cat")
      assert.falsy(err)
      assert.same("also animal", ok)

      -- when - resetting redis
      redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)

      -- then - clears everything
      red:select(REDIS_DATABASE1)
      local ok, err = red:get("dog")
      assert.falsy(err)
      assert.same(ngx.null, ok)

      red:select(REDIS_DATABASE2)
      local ok, err = red:get("cat")
      assert.falsy(err)
      assert.same(ngx.null, ok)
    end)
  end)
end)

