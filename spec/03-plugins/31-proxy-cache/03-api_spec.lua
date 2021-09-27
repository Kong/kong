local helpers = require "spec.helpers"
local myhelpers = require "spec.03-plugins.31-proxy-cache.myhelpers"
local strategies = require("kong.plugins.proxy-cache.strategies")
local cjson = require "cjson"

local strategy_wait_disappear = myhelpers.wait_disappear
local strategy_wait_appear = myhelpers.wait_appear

local configs = {
  memory = {
    dictionary_name = "kong",
  },
  redis = {
    host = helpers.redis_host,
    port = 6379,
  },
}
for _, policy in ipairs(strategies.STRATEGY_TYPES) do
  describe("Plugin: proxy-cache with policy: " .. policy, function()
  local bp
  local proxy_client, admin_client, cache_key, plugin1, route1
    local policy_config = configs[policy]

    local strategy = strategies({
      strategy_name = policy,
      strategy_opts = policy_config,
    })

  setup(function()
    bp = helpers.get_db_utils(nil, nil, {"proxy-cache"})

    route1 = assert(bp.routes:insert {
      hosts = { "route-1.com" },
    })
    plugin1 = assert(bp.plugins:insert {
      name = "proxy-cache",
      route = { id = route1.id },
      config = {
        strategy = policy,
        content_type = { "text/plain", "application/json" },
        [policy] = policy_config,
      },
    })

    -- an additional plugin does not interfere with the iteration in
    -- the global /proxy-cache API handler: regression test for
    -- https://github.com/Kong/kong-plugin-proxy-cache/issues/12
    assert(bp.plugins:insert {
      name = "request-transformer",
    })

    local route2 = assert(bp.routes:insert {
      hosts = { "route-2.com" },
    })

    assert(bp.plugins:insert {
      name = "proxy-cache",
      route = { id = route2.id },
      config = {
        strategy = policy,
        content_type = { "text/plain", "application/json" },
        [policy] = policy_config,
      },
    })

    assert(helpers.start_kong({
      plugins = "proxy-cache,request-transformer",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    if admin_client then
      admin_client:close()
    end
    if proxy_client then
      proxy_client:close()
    end

    admin_client = helpers.admin_client()
    proxy_client = helpers.proxy_client()
    strategy:flush(true)
  end)

  teardown(function()
    helpers.stop_kong(nil, true)
  end)

  describe("(schema)", function()
    local body

    it("accepts an array of numbers as strings", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "proxy-cache",
          config = {
            strategy = policy,
            [policy] = policy_config,
            response_code = {123, 200},
            cache_ttl = 600,
            request_method = { "GET" },
            content_type = { "text/json" },
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      body = assert.res_status(201, res)
    end)
    it("casts an array of response_code values to number types", function()
      local json = cjson.decode(body)
      for _, v in ipairs(json.config.response_code) do
        assert.is_number(v)
      end
    end)
    it("errors if response_code is an empty array", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "proxy-cache",
          config = {
            strategy = policy,
            [policy] = policy_config,
            response_code = {},
            cache_ttl = 600,
            request_method = { "GET" },
            content_type = { "text/json" },
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(400, res)
      local json_body = cjson.decode(body)
      assert.same("length must be at least 1", json_body.fields.config.response_code)
    end)
    it("errors if response_code is a string", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "proxy-cache",
          config = {
            strategy = policy,
            [policy] = policy_config,
            response_code = {},
            cache_ttl = 600,
            request_method = "GET",
            content_type = "text/json",
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(400, res)
      local json_body = cjson.decode(body)
      assert.same("length must be at least 1", json_body.fields.config.response_code)
    end)
    it("errors if response_code has non-numeric values", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "proxy-cache",
          config = {
            strategy = policy,
            [policy] = policy_config,
            response_code = {true, "alo", 123},
            cache_ttl = 600,
            request_method = "GET",
            content_type = "text/json",
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(400, res)
      local json_body = cjson.decode(body)
      assert.same( { "expected an integer", "expected an integer" },
                   json_body.fields.config.response_code)
    end)
    it("errors if response_code has float value", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "proxy-cache",
          config = {
            strategy = policy,
            [policy] = policy_config,
            response_code = {90},
            cache_ttl = 600,
            request_method = "GET",
            content_type = "text/json",
          },
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      local body = assert.res_status(400, res)
      local json_body = cjson.decode(body)
      assert.same({ "value should be between 100 and 900" },
                   json_body.fields.config.response_code)
    end)
  end)
  describe("(API)", function()
    describe("DELETE", function()
      it("delete a cache entry", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        -- cache key is an md5sum of the prefix uuid, method, and $request
        local cache_key1 = res.headers["X-Cache-Key"]
        assert.matches("^[%w%d]+$", cache_key1)
        assert.equals(32, #cache_key1)
        strategy_wait_appear(policy, strategy, cache_key1)

        res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        local cache_key2 = res.headers["X-Cache-Key"]
        assert.same(cache_key1, cache_key2)

        -- delete the key
        res = assert(admin_client:send {
          method = "DELETE",
          path = "/proxy-cache/" .. plugin1.id .. "/caches/" .. cache_key1,
        })
        assert.res_status(204, res)

        strategy_wait_disappear(policy, strategy, cache_key1)
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        -- delete directly, having to look up all proxy-cache instances
        res = assert(admin_client:send {
          method = "DELETE",
          path = "/proxy-cache/" .. cache_key1,
        })
        assert.res_status(204, res)
        strategy_wait_disappear(policy, strategy, cache_key1)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        strategy_wait_appear(policy, strategy, cache_key1)
      end)
      it("purge all the cache entries", function()
        -- make a `Hit` request to `route-1`
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })
        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

        -- make a `Miss` request to `route-2`
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-2.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        -- cache key is an md5sum of the prefix uuid, method, and $request
        local cache_key1 = res.headers["X-Cache-Key"]
        assert.matches("^[%w%d]+$", cache_key1)
        assert.equals(32, #cache_key1)

        -- make a `Hit` request to `route-2`
        strategy_wait_appear(policy, strategy, cache_key1)
        res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-2.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        local cache_key2 = res.headers["X-Cache-Key"]
        assert.same(cache_key1, cache_key2)

        -- delete all the cache keys
        res = assert(admin_client:send {
          method = "DELETE",
          path = "/proxy-cache",
        })
        assert.res_status(204, res)

        strategy_wait_disappear(policy, strategy, cache_key1)
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-2.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
      end)
      it("delete a non-existing cache key", function()
        -- delete all the cache keys
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/proxy-cache",
        })
        assert.res_status(204, res)

        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/proxy-cache/" .. plugin1.id .. "/caches/" .. "123",
        })
        assert.res_status(404, res)
      end)
      it("delete a non-existing plugins's cache key", function()
        -- delete all the cache keys
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/proxy-cache",
        })
        assert.res_status(204, res)

        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/proxy-cache/" .. route1.id .. "/caches/" .. "123",
        })
        assert.res_status(404, res)
      end)
    end)
    describe("GET", function()
      it("get a non-existing cache", function()
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        local cache_key = res.headers["X-Cache-Key"]
        -- delete all the cache keys
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/proxy-cache",
        })
        assert.res_status(204, res)

        local res = assert(admin_client:send {
          method = "GET",
          path = "/proxy-cache/" .. plugin1.id .. "/caches/" .. cache_key,
        })
        assert.res_status(404, res)

        -- attempt to list an entry directly via cache key
        local res = assert(admin_client:send {
          method = "GET",
          path = "/proxy-cache/" .. cache_key,
        })
        assert.res_status(404, res)
      end)
      it("get a existing cache", function()
        -- add request to cache
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })
        assert.res_status(200, res)
          cache_key = res.headers["X-Cache-Key"]
          strategy_wait_appear(policy, strategy, cache_key)

        local res = assert(admin_client:send {
          method = "GET",
          path = "/proxy-cache/" .. plugin1.id .. "/caches/" .. cache_key,
        })
        local body = assert.res_status(200, res)
        local json_body = cjson.decode(body)
        assert.same(cache_key, json_body.headers["X-Cache-Key"])

        -- list an entry directly via cache key
        local res = assert(admin_client:send {
          method = "GET",
          path = "/proxy-cache/" ..  cache_key,
        })
        local body = assert.res_status(200, res)
        local json_body = cjson.decode(body)
        assert.same(cache_key, json_body.headers["X-Cache-Key"])
      end)
    end)
  end)
end)
end
