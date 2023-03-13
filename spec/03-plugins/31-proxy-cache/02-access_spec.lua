local helpers = require "spec.helpers"
local strategies = require("kong.plugins.proxy-cache.strategies")


--local TIMEOUT = 10 -- default timeout for non-memory strategies

-- use wait_until spec helper only on async strategies
--local function strategy_wait_until(strategy, func, timeout)
--  if strategies.DELAY_STRATEGY_STORE[strategy] then
--    helpers.wait_until(func, timeout)
--  end
--end


do
  local policy = "memory"
  describe("proxy-cache access with policy: " .. policy, function()
    local client, admin_client
    --local cache_key
    local policy_config = { dictionary_name = "kong", }

    local strategy = strategies({
      strategy_name = policy,
      strategy_opts = policy_config,
    })

    setup(function()

      local bp = helpers.get_db_utils(nil, nil, {"proxy-cache"})
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
      local route17 = assert(bp.routes:insert({
        hosts = { "route-17.com" },
      }))
      local route18 = assert(bp.routes:insert({
        hosts = { "route-18.com" },
      }))
      local route19 = assert(bp.routes:insert({
        hosts = { "route-19.com" },
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
        name = "proxy-cache",
        route = { id = route1.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
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

      -- global plugin for routes 3 and 4
      assert(bp.plugins:insert {
        name = "proxy-cache",
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache",
        route = { id = route5.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache",
        route = { id = route6.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_ttl = 2,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache",
        route = { id = route7.id },
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_control = true,
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache",
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
        name = "proxy-cache",
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
        name = "proxy-cache",
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
        name = "proxy-cache",
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
        name = "proxy-cache",
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

      assert(bp.plugins:insert {
        name = "proxy-cache",
        route = { id = route17.id },
        config = {
          strategy = policy,
          [policy] = policy_config,
          content_type = { "*/*" },
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache",
        route = { id = route18.id },
        config = {
          strategy = policy,
          [policy] = policy_config,
          content_type = { "application/xml; charset=UTF-8" },
        },
      })

      assert(bp.plugins:insert {
        name = "proxy-cache",
        route = { id = route19.id },
        config = {
          strategy = policy,
          [policy] = policy_config,
          content_type = { "application/xml;" }, -- invalid content_type
        },
      })

      assert(helpers.start_kong({
        plugins = "bundled",
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

      -- cache key is a sha256sum of the prefix uuid, method, and $request
      local cache_key1 = res.headers["X-Cache-Key"]
      assert.matches("^[%w%d]+$", cache_key1)
      assert.equals(64, #cache_key1)

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key1) ~= nil
      --end, TIMEOUT)

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
      --cache_key = cache_key1
    end)

    it("respects cache ttl", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-6.com",
        }
      })

      --local cache_key2 = res.headers["X-Cache-Key"]
      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key2) ~= nil
      --end, TIMEOUT)

      res = client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-6.com",
        }
      }

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])
      --local cache_key = res.headers["X-Cache-Key"]

      -- if strategy is local, it's enough to simply use a sleep
      if strategies.LOCAL_DATA_STRATEGIES[policy] then
        ngx.sleep(3)
      end

      -- wait until the strategy expires the object for the given
      -- cache key
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) == nil
      --end, TIMEOUT)

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
      --cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) ~= nil
      --end, TIMEOUT)

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
      --cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) ~= nil
      --end, TIMEOUT)

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "route-9.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- if strategy is local, it's enough to simply use a sleep
      if strategies.LOCAL_DATA_STRATEGIES[policy] then
        ngx.sleep(3)
      end

      -- give ourselves time to expire
      -- as storage_ttl > cache_ttl, the object still remains in storage
      -- in an expired state
      --strategy_wait_until(policy, function()
      --  local obj = strategy:fetch(cache_key)
      --  return ngx.time() - obj.timestamp > obj.ttl
      --end, TIMEOUT)

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
      --local cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) ~= nil
      --end, TIMEOUT)

      res = assert(client:send {
        method = "GET",
        path = "/cache/2",
        headers = {
          host = "route-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- if strategy is local, it's enough to simply use a sleep
      if strategies.LOCAL_DATA_STRATEGIES[policy] then
        ngx.sleep(3)
      end

      -- give ourselves time to expire
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) == nil
      --end, TIMEOUT)

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
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) ~= nil
      --end, TIMEOUT)

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
        --local cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        --strategy_wait_until(policy, function()
        --  return strategy:fetch(cache_key) ~= nil
        --end, TIMEOUT)

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
        --local cache_key = res.headers["X-Cache-Key"]

        -- if strategy is local, it's enough to simply use a sleep
        if strategies.LOCAL_DATA_STRATEGIES[policy] then
          ngx.sleep(3)
        end

        -- wait until max-age
        --strategy_wait_until(policy, function()
        --  local obj = strategy:fetch(cache_key)
        --  return ngx.time() - obj.timestamp > 2
        --end, TIMEOUT)

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
        --local cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        --strategy_wait_until(policy, function()
        --  return strategy:fetch(cache_key) ~= nil
        --end, TIMEOUT)

        res = assert(client:send {
          method = "GET",
          path = "/cache/2",
          headers = {
            host = "route-8.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

        -- if strategy is local, it's enough to simply use a sleep
        if strategies.LOCAL_DATA_STRATEGIES[policy] then
          ngx.sleep(4)
        end

        -- wait for longer than max-stale below
        --strategy_wait_until(policy, function()
        --  local obj = strategy:fetch(cache_key)
        --  return ngx.time() - obj.timestamp - obj.ttl > 2
        --end, TIMEOUT)

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

      it("only-if-cached", function()
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
      --local cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) ~= nil
      --end, TIMEOUT)

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
      assert.equals(64, #cache_key1)

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

    it("differentiates caches between instances", function()
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
      assert.equals(64, #cache_key1)

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key1) ~= nil
      --end, TIMEOUT)

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

      res = assert(client:send {
        method = "GET",
        path = "/get?a=c",
        headers = {
          host = "route-1.com",
        }
      })

      assert.res_status(200, res)

      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get?b=c&a=b",
        headers = {
          host = "route-1.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get?a&b",
        headers = {
          host = "route-1.com",
        }
      })
      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get?a&b",
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

      --local cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) ~= nil
      --end, TIMEOUT)

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
      --local cache_key = res.headers["X-Cache-Key"]

      -- wait until the underlying strategy converges
      --strategy_wait_until(policy, function()
      --  return strategy:fetch(cache_key) ~= nil
      --end, TIMEOUT)

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
        --local cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        --strategy_wait_until(policy, function()
        --  return strategy:fetch(cache_key) ~= nil
        --end, TIMEOUT)

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
        --cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        --strategy_wait_until(policy, function()
        --  return strategy:fetch(cache_key) ~= nil
        --end, TIMEOUT)

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

    describe("content-type", function()
      it("should cache a request with wildcard content_type(*/*)", function()
        local request = {
          method = "GET",
          path = "/xml",
          headers = {
            host = "route-17.com",
          },
        }

        local res = assert(client:send(request))
        assert.res_status(200, res)
        assert.same("application/xml", res.headers["Content-Type"])
        assert.same("Miss", res.headers["X-Cache-Status"])

        local res = assert(client:send(request))
        assert.res_status(200, res)
        assert.same("application/xml", res.headers["Content-Type"])
        assert.same("Hit", res.headers["X-Cache-Status"])
      end)

      it("should not cache a request while parameter is not match", function()
        local res = assert(client:send {
          method = "GET",
          path = "/xml",
          headers = {
            host = "route-18.com",
          },
        })

        assert.res_status(200, res)
        assert.same("application/xml", res.headers["Content-Type"])
        assert.same("Bypass", res.headers["X-Cache-Status"])
      end)


      it("should not cause error while upstream returns a invalid content type", function()
        local res = assert(client:send {
          method = "GET",
          path = "/response-headers?Content-Type=application/xml;",
          headers = {
            host = "route-18.com",
          },
        })

        assert.res_status(200, res)
        assert.same("application/xml;", res.headers["Content-Type"])
        assert.same("Bypass", res.headers["X-Cache-Status"])
      end)

      it("should not cause error while config.content_type has invalid element", function()
        local res, err = client:send {
          method = "GET",
          path = "/xml",
          headers = {
            host = "route-19.com",
          },
        }

        assert.is_nil(err)
        assert.res_status(200, res)
        assert.same("application/xml", res.headers["Content-Type"])
        assert.same("Bypass", res.headers["X-Cache-Status"])
      end)
    end)
  end)
end
