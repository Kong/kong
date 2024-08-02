-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- unit test for openid-connect cache strategy

local redis_strategy = require("kong.plugins.openid-connect.cache.strategy.redis")
local helpers = require "spec.helpers"
local REDIS_HOST = helpers.redis_host
local REDIS_PORT = helpers.redis_port
local redis = require("resty.redis")
local cjson = require("cjson.safe")

describe("OpenID Connect cache strategy", function()
  describe("Redis strategy", function()
    it("works", function()
      local red = redis:new()
      assert(red:connect(REDIS_HOST, REDIS_PORT))
      finally(function()
        red:close()
      end)

      red:flushall()
      red:set("irrelevant_key", "value")

      local strategy = redis_strategy.new({
        host = REDIS_HOST,
        port = REDIS_PORT,
        prefix = "ttt::",
      })

      assert.truthy(strategy:set("foo", "bar", 1))
      assert.same(
        { "bar", nil, 1 },
        { strategy:get("foo") }
      )

      assert.equal([["bar"]], red:get("ttt::foo"))
      assert.truthy(red:expire("ttt::foo", 1))

      -- wait until key expires
      ngx.sleep(2)

      assert.falsy(strategy:get("foo"))
      assert.equal(ngx.null, red:get("ttt::foo"))


      local t = { as = { "bar1", "bar2" } }

      assert.truthy(strategy:set("foo1", t))
      assert.same(
        { t, nil, nil },
        { strategy:get("foo1") }
      )

      local json_foo1, err = red:get("ttt::foo1")
      assert.truthy(json_foo1, err)
      assert.same(t, cjson.decode(json_foo1))

      assert.equal(-1, red:ttl("ttt::foo1"))

      assert.truthy(strategy:del("foo1"))
      assert.same(
        { nil, nil, nil },
        { strategy:get("foo1") }
      )
      assert.equal(ngx.null, red:get("ttt::foo1"))

      assert.truthy(strategy:set("relevant1", "1"))
      assert.truthy(strategy:set("relevant2", "1"))

      assert.truthy(strategy:get("relevant1"))
      assert.truthy(strategy:get("relevant2"))

      assert.truthy(strategy:purge())
      assert.falsy(strategy:get("relevant1"))
      assert.falsy(strategy:get("relevant2"))

      assert.equal("value", red:get("irrelevant_key"))
    end)
  end)
end)
