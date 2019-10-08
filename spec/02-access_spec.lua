local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local strategies = require("kong.plugins.proxy-cache-advanced.strategies")
local cjson   = require "cjson"


local TIMEOUT = 10 -- default timeout for non-memory strategies


local REDIS_HOST = helpers.redis_host
local REDIS_PORT = 6379
local REDIS_DATABASE = 1


for i, policy in ipairs({"memory", "redis"}) do
  describe("proxy-cache-advanced access with policy: " .. policy, function()
    local client, admin_client
    local policy_config
    local cache_key

    if policy == "memory" then
      policy_config = {
        dictionary_name = "kong",
      }
    elseif policy == "redis" then
      policy_config = {
        host = REDIS_HOST,
        port = REDIS_PORT,
        database = REDIS_DATABASE,
      }
    end

    local strategy = strategies({
      strategy_name = policy,
      strategy_opts = policy_config,
    })

    -- These wait functions use the plugin API to retrieve the cache entry
    -- and expose it to the function passed.
    -- Trying to access the strategy:fetch works for redis, but not for the
    -- in memory cache.
    local function wait_until_key(key, func)
      helpers.wait_until(function()
        local res = admin_client:send {
          method = "GET",
          path   = "/proxy-cache-advanced/" .. key
        }
        -- wait_until does not like asserts
        if not res then return false end

        local body = res:read_body()

        return func(res, body)
      end, TIMEOUT)
    end

    -- wait until key is in cache (we get a 200 on plugin API) and execute
    -- a test function if provided.
    local function wait_until_key_in_cache(key, func)
      local func = func or function(obj) return true end
      wait_until_key(key, function(res, body)
        if res.status == 200 then
          local obj = cjson.decode(body)
          return func(obj)
        end

        return false
      end)
    end

    local function wait_until_key_not_in_cache(key)
      wait_until_key(key, function(res)
        -- API endpoint returns either 200, 500 or 404
        return res.status > 200
      end)
    end

    setup(function()

      local bp = helpers.get_db_utils(nil, nil, {"proxy-cache-advanced"})
      strategy:flush(true)

      local route1 = assert(bp.routes:insert {
        hosts = { "route-1.com" },
      })
      local route2 = assert(bp.routes:insert {
        hosts = { "route-2.com" },
      })
      assert(bp.routes:insert {
        hosts = { "route-3.com" },
      })
      assert(bp.routes:insert {
        hosts = { "route-4.com" },
      })
      local route5 = assert(bp.routes:insert {
        hosts = { "route-5.com" },
      })
      local route6 = assert(bp.routes:insert {
        hosts = { "route-6.com" },
      })
      local route7 = assert(bp.routes:insert {
        hosts = { "route-7.com" },
      })
      local route8 = assert(bp.routes:insert {
        hosts = { "route-8.com" },
      })
      local route9 = assert(bp.routes:insert {
        hosts = { "route-9.com" },
      })
      local route10 = assert(bp.routes:insert {
        hosts = { "route-10.com" },
      })
      local route11 = assert(bp.routes:insert {
        hosts = { "route-11.com" },
      })
      local route12 = assert(bp.routes:insert {
        hosts = { "route-12.com" },
      })
      local route13 = assert(bp.routes:insert {
        hosts = { "route-13.com" },
      })
      local route14 = assert(bp.routes:insert {
        hosts = { "route-14.com" },
      })
      local route15 = assert(bp.routes:insert({
        hosts = { "route-15.com" },
      }))
      local route16 = assert(bp.routes:insert({
        hosts = { "route-16.com" },
      }))

      local consumer1 = assert(bp.consumers:insert {
        username = "bob",
      })
      assert(bp.keyauth_credentials:insert {
        key = "bob",
        consumer = { id = consumer1.id },
      })
      local consumer2 = assert(bp.consumers:insert {
        username = "alice",
      })
      assert(bp.keyauth_credentials:insert {
        key = "alice",
        consumer = { id = consumer2.id },
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route5.id },
        config = {},
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route13.id },
        config = {},
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route14.id },
        config = {},
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route15.id },
        config = {},
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route16.id },
        config = {},
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route1.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route2.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      -- global plugin for routes 3 and 4
      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route5.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route6.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_ttl = 2,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route7.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_control = true,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route8.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_control = true,
          storage_ttl = 600,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route9.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_ttl = 2,
          storage_ttl = 60,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route10.id },
        config = {
          strategy = policy,
          content_type = { "text/html; charset=utf-8", "application/json" },
          response_code = { 200, 417 },
          request_method = { "GET", "HEAD", "POST" },
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route11.id },
        config = {
          strategy = policy,
          [policy] = policy_config,
          content_type = { "text/plain", "application/json" },
          response_code = { 200 },
          request_method = { "GET", "HEAD", "POST" },
          vary_headers = {"foo"}
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache-advanced",
        route = { id = route12.id },
        config = {
          strategy = policy,
          [policy] = policy_config,
          content_type = { "text/plain", "application/json" },
          response_code = { 200 },
          request_method = { "GET", "HEAD", "POST" },
          vary_query_params = {"foo"}
        },
      })

      assert(helpers.start_kong({
        plugins = "bundled,proxy-cache-advanced",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)


    before_each(function()
      if client then
        client:close()
      end
      if admin_client then
        admin_client:close()
      end
      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)


    teardown(function()
      if client then
        client:close()
      end

      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong(nil, true)
    end)

    it("caches a simple request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        }
      })

      local body1 = assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      -- cache key is an md5sum of the prefix uuid, method, and $request
      local cache_key1 = res.headers["X-Cache-Key"]
      assert.matches("^[%w%d]+$", cache_key1)
      assert.equals(32, #cache_key1)

      wait_until_key_in_cache(cache_key1)

      local res = client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-1.com",
        }
      }

      local body2 = assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      local cache_key2 = res.headers["X-Cache-Key"]
      assert.same(cache_key1, cache_key2)

      -- assert that response bodies are identical
      assert.same(body1, body2)

      -- examine this cache key against another plugin's cache key for the same req
      cache_key = cache_key1
    end)

    it("respects cache ttl", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-6.com",
        }
      })

      local cache_key2 = res.headers["X-Cache-Key"]
      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      wait_until_key_in_cache(cache_key2)

      res = client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-6.com",
        }
      }

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      local cache_key = res.headers["X-Cache-Key"]

      -- wait until the strategy expires the object for the given
      -- cache key
      wait_until_key_not_in_cache(cache_key)

      -- and go through the cycle again
      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-6.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
      cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-6.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- examine the behavior of keeping cache in memory for longer than ttl
      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-9.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
      cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-9.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- give ourselves time to expire
      -- as storage_ttl > cache_ttl, the object still remains in storage
      -- in an expired state
      wait_until_key_in_cache(cache_key, function(obj)
        return ngx.time() - obj.timestamp > obj.ttl
      end)

      -- and go through the cycle again
      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-9.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Refresh", res.headers["X-Cache-Status"])

      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-9.com",
        }
      })


      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
    end)

    it("respects cache ttl via cache control", function()
      local res = assert(client:send {
        method = "GET",
        path = "/cache/2",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
      local cache_key = res.headers["X-Cache-Key"]

      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/cache/2",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- give ourselves time to expire
      wait_until_key_not_in_cache(cache_key)

      -- and go through the cycle again
      res = assert(client:send {
        method = "GET",
        path = "/cache/2",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/cache/2",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- assert that max-age=0 never results in caching
      res = assert(client:send {
        method = "GET",
        path = "/cache/0",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Bypass", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/cache/0",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Bypass", res.headers["X-Cache-Status"])
    end)

    it("public not present in Cache-Control, but max-age is", function()
      -- httpbin's /cache endpoint always sets "Cache-Control: public"
      -- necessary to set it manually using /response-headers instead
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?Cache-Control=max-age%3D604800",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
    end)

    it("Cache-Control contains s-maxage only", function()
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?Cache-Control=s-maxage%3D604800",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
    end)

    it("Expires present, Cache-Control absent", function()
      local httpdate = ngx.escape_uri(os.date("!%a, %d %b %Y %X %Z", os.time()+5000))
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers",
        query = "Expires=" .. httpdate,
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
    end)

    describe("respects cache-control", function()
      it("min-fresh", function()
        -- bypass via unsatisfied min-fresh
        local res = assert(client:send {
          method = "GET",
          path = "/cache/2",
          headers = {
            host = "route-7.com",
            ["Cache-Control"] = "min-fresh=30"
          }
        })

        assert.res_status(200, res)
        assert.same("Refresh", res.headers["X-Cache-Status"])
      end)

      it("max-age", function()
        local res = assert(client:send {
          method = "GET",
          path = "/cache/10",
          headers = {
            host = "route-7.com",
            ["Cache-Control"] = "max-age=2"
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        local cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "GET",
          path = "/cache/10",
          headers = {
            host = "route-7.com",
            ["Cache-Control"] = "max-age=2"
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        local cache_key = res.headers["X-Cache-Key"]

        -- wait until max-age
        wait_until_key_in_cache(cache_key, function(obj)
          return ngx.time() - obj.timestamp > 2
        end, TIMEOUT)

        res = assert(client:send {
          method = "GET",
          path = "/cache/10",
          headers = {
            host = "route-7.com",
            ["Cache-Control"] = "max-age=2"
          }
        })

        assert.res_status(200, res)
        assert.same("Refresh", res.headers["X-Cache-Status"])
      end)

      it("max-stale", function()
        local res = assert(client:send {
          method = "GET",
          path = "/cache/2",
          headers = {
            host = "route-8.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        local cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "GET",
          path = "/cache/2",
          headers = {
            host = "route-8.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

        -- wait for longer than max-stale below
        wait_until_key_in_cache(cache_key, function(obj)
          return ngx.time() - obj.timestamp - obj.ttl > 2
        end)

        res = assert(client:send {
          method = "GET",
          path = "/cache/2",
          headers = {
            host = "route-8.com",
            ["Cache-Control"] = "max-stale=1",
          }
        })

        assert.res_status(200, res)
        assert.same("Refresh", res.headers["X-Cache-Status"])
      end)

      it("#o only-if-cached", function()
        local res = assert(client:send {
          method = "GET",
          path   = "/get?not=here",
          headers = {
            host = "route-8.com",
            ["Cache-Control"] = "only-if-cached",
          }
        })

        assert.res_status(504, res)
      end)
    end)

    it("caches a streaming request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/stream/3",
        headers = {
          host = "route-1.com",
        }
      })

      local body1 = assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
      assert.is_nil(res.headers["Content-Length"])
      local cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/stream/3",
        headers = {
          host = "route-1.com",
        }
      })

      local body2 = assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      assert.same(body1, body2)
    end)

    it("uses a separate cache key for the same consumer between routes", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-13.com",
          apikey = "bob",
        }
      })
      assert.res_status(200, res)
      local cache_key1 = res.headers["X-Cache-Key"]

      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-14.com",
          apikey = "bob",
        }
      })
      assert.res_status(200, res)
      local cache_key2 = res.headers["X-Cache-Key"]

      assert.not_equal(cache_key1, cache_key2)
    end)

    it("uses a separate cache key for the same consumer between routes/services", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-15.com",
          apikey = "bob",
        }
      })
      assert.res_status(200, res)
      local cache_key1 = res.headers["X-Cache-Key"]

      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-16.com",
          apikey = "bob",
        }
      })
      assert.res_status(200, res)
      local cache_key2 = res.headers["X-Cache-Key"]

      assert.not_equal(cache_key1, cache_key2)
    end)

    it("uses an separate cache key between routes-specific and a global plugin", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-3.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      local cache_key1 = res.headers["X-Cache-Key"]
      assert.matches("^[%w%d]+$", cache_key1)
      assert.equals(32, #cache_key1)

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-4.com",
        }
      })

      assert.res_status(200, res)

      assert.same("Miss", res.headers["X-Cache-Status"])
      local cache_key2 = res.headers["X-Cache-Key"]
      assert.not_same(cache_key1, cache_key2)
    end)

    it("#o differentiates caches between instances", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-2.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      local cache_key1 = res.headers["X-Cache-Key"]
      assert.matches("^[%w%d]+$", cache_key1)
      assert.equals(32, #cache_key1)

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key1)

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-2.com",
        }
      })

      local cache_key2 = res.headers["X-Cache-Key"]
      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      assert.same(cache_key1, cache_key2)
    end)

    it("uses request params as part of the cache key", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get?a=b&b=c",
        headers = {
          host = "route-1.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
      local cache_key = res.headers["X-Cache-Key"]

      res = assert(client:send {
        method = "GET",
        path = "/get?a=c",
        headers = {
          host = "route-1.com",
        }
      })

      assert.res_status(200, res)

      assert.same("Miss", res.headers["X-Cache-Status"])

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/get?b=c&a=b",
        headers = {
          host = "route-1.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
    end)

    it("can focus only in a subset of the query arguments", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get?foo=b&b=c",
        headers = {
          host = "route-12.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      local cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/get?b=d&foo=b",
        headers = {
          host = "route-12.com",
        }
      })

      assert.res_status(200, res)

      assert.same("Hit", res.headers["X-Cache-Status"])
    end)

    it("uses headers if instructed to do so", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-11.com",
          foo = "bar"
        }
      })
      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
      local cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      wait_until_key_in_cache(cache_key)

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-11.com",
          foo = "bar"
        }
      })
      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-11.com",
          foo = "baz"
        }
      })
      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
    end)

    describe("handles authenticated routes", function()
      it("by ignoring cache if the request is unauthenticated", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-5.com",
          }
        })

        assert.res_status(401, res)
        assert.is_nil(res.headers["X-Cache-Status"])
      end)

      it("by maintaining a separate cache per consumer", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-5.com",
            apikey = "bob",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        local cache_key = res.headers["X-Cache-Key"]
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-5.com",
            apikey = "bob",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-5.com",
            apikey = "alice",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        local cache_key = res.headers["X-Cache-Key"]
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-5.com",
            apikey = "alice",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

      end)
    end)

    describe("bypasses cache for uncacheable requests: ", function()
      it("request method", function()
        local res = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "route-1.com",
            ["Content-Type"] = "application/json",
          },
          {
            foo = "bar",
          },
        })

        assert.res_status(200, res)
        assert.same("Bypass", res.headers["X-Cache-Status"])
      end)
    end)

    describe("bypasses cache for uncacheable responses:", function()
      it("response status", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/418",
          headers = {
            host = "route-1.com",
          },
        })

        assert.res_status(418, res)
        assert.same("Bypass", res.headers["X-Cache-Status"])
      end)

      it("response content type", function()
        local res = assert(client:send {
          method = "GET",
          path = "/xml",
          headers = {
            host = "route-1.com",
          },
        })

        assert.res_status(200, res)
        assert.same("Bypass", res.headers["X-Cache-Status"])
      end)
    end)

    describe("caches non-default", function()
      it("request methods", function()
        local res = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "route-10.com",
            ["Content-Type"] = "application/json",
          },
          {
            foo = "bar",
          },
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        local cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "route-10.com",
            ["Content-Type"] = "application/json",
          },
          {
            foo = "bar",
          },
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
      end)

      it("response status", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/417",
          headers = {
            host = "route-10.com",
          },
        })

        assert.res_status(417, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        local cache_key = res.headers["X-Cache-Key"]
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "GET",
          path = "/status/417",
          headers = {
            host = "route-10.com",
          },
        })


        assert.res_status(417, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
      end)

    end)

    describe("cache versioning", function()
      local cache_key

      -- This test tries to flush the proxy-cache from the test
      -- code. This is is doable in the redis strategy as it can be
      -- referenced (and flushed) from test code. nginx's in-memory
      -- cache can't be referenced from test code.
      local test_except_memory = policy == "memory" and pending or it
      test_except_memory("bypasses old cache version data", function()
        strategy:flush(true)

        -- prime the cache and mangle its versioning
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        wait_until_key_in_cache(cache_key)

        local cache = strategy:fetch(cache_key) or {}
        cache.version = "yolo"
        strategy:store(cache_key, cache, 10)

        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Bypass", res.headers["X-Cache-Status"])

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches("[proxy-cache-advanced] cache format mismatch, purging " .. cache_key,
                       err_log, nil, true)
      end)
    end)

    describe("displays Kong core headers:", function()
      it("X-Kong-Proxy-Latency", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get?show-me=proxy-latency",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        assert.matches("^%d+$", res.headers["X-Kong-Proxy-Latency"])

        local cache_key = res.headers["X-Cache-Key"]
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "GET",
          path = "/get?show-me=proxy-latency",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        assert.matches("^%d+$", res.headers["X-Kong-Proxy-Latency"])
      end)

      it("X-Kong-Upstream-Latency", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get?show-me=upstream-latency",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        assert.matches("^%d+$", res.headers["X-Kong-Upstream-Latency"])
        cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "GET",
          path = "/get?show-me=upstream-latency",
          headers = {
            host = "route-1.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        assert.matches("^%d+$", res.headers["X-Kong-Upstream-Latency"])
      end)
    end)
  end)
end
