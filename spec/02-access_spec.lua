local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local redis = require "kong.enterprise_edition.redis"

local REDIS_HOST = "127.0.0.1"
local REDIS_PORT = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 1

for i, policy in ipairs({"memory", "redis"}) do
  describe("proxy-cache access with policy: " .. policy, function()
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
        password = REDIS_PASSWORD,
      }
    end

    setup(function()

      local _, _, dao = helpers.get_db_utils()
      redis.flush_redis(REDIS_HOST, REDIS_PORT, REDIS_DATABASE, REDIS_PASSWORD)

      local api1 = assert(dao.apis:insert {
        name = "api-1",
        hosts = { "api-1.com" },
        upstream_url = "http://httpbin.org",
      })
      local api2 = assert(dao.apis:insert {
        name = "api-2",
        hosts = { "api-2.com" },
        upstream_url = "http://httpbin.org",
      })
      assert(dao.apis:insert {
        name = "api-3",
        hosts = { "api-3.com" },
        upstream_url = "http://httpbin.org",
      })
      assert(dao.apis:insert {
        name = "api-4",
        hosts = { "api-4.com" },
        upstream_url = "http://httpbin.org",
      })
      local api5 = assert(dao.apis:insert {
        name = "api-5",
        hosts = { "api-5.com" },
        upstream_url = "http://httpbin.org",
      })
      local api6 = assert(dao.apis:insert {
        name = "api-6",
        hosts = { "api-6.com" },
        upstream_url = "http://httpbin.org",
      })
      local api7 = assert(dao.apis:insert {
        name = "api-7",
        hosts = { "api-7.com" },
        upstream_url = "http://httpbin.org",
      })
      local api8 = assert(dao.apis:insert {
        name = "api-8",
        hosts = { "api-8.com" },
        upstream_url = "http://httpbin.org",
      })
      local api9 = assert(dao.apis:insert {
        name = "api-9",
        hosts = { "api-9.com" },
        upstream_url = "http://httpbin.org",
      })
      local api10 = assert(dao.apis:insert {
        name = "api-10",
        hosts = { "api-10.com" },
        upstream_url = "http://httpbin.org",
      })
      local api11 = assert(dao.apis:insert {
        name = "api-11",
        hosts = { "api-11.com" },
        upstream_url = "http://httpbin.org",
      })
      local api12 = assert(dao.apis:insert {
        name = "api-12",
        hosts = { "api-12.com" },
        upstream_url = "http://httpbin.org",
      })

      local consumer1 = assert(dao.consumers:insert {
        username = "bob",
      })
      assert(dao.keyauth_credentials:insert {
        key = "bob",
        consumer_id = consumer1.id,
      })
      local consumer2 = assert(dao.consumers:insert {
        username = "alice",
      })
      assert(dao.keyauth_credentials:insert {
        key = "alice",
        consumer_id = consumer2.id,
      })
      assert(dao.plugins:insert {
        name = "key-auth",
        api_id = api5.id,
        config = {},
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api1.id,
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api2.id,
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      -- global plugin for apis 3 and 4
      assert(dao.plugins:insert {
        name = "proxy-cache",
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api5.id,
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api6.id,
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_ttl = 2,
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api7.id,
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_control = true,
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api8.id,
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_control = true,
          storage_ttl = 600,
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api9.id,
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          [policy] = policy_config,
          cache_ttl = 2,
          storage_ttl = 60,
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api10.id,
        config = {
          strategy = policy,
          content_type = { "text/plain", "application/json" },
          response_code = { 200, 418 },
          request_method = { "GET", "HEAD", "POST" },
          [policy] = policy_config,
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api11.id,
        config = {
          strategy = policy,
          [policy] = policy_config,
          content_type = { "text/plain", "application/json" },
          response_code = { 200 },
          request_method = { "GET", "HEAD", "POST" },
          vary_headers = {"foo"}
        },
      })

      assert(dao.plugins:insert {
        name = "proxy-cache",
        api_id = api12.id,
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
        custom_plugins = "proxy-cache",
      }))
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

      helpers.stop_kong()
    end)

    it("caches a simple request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-1.com",
        }
      })

      local body1 = assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      -- cache key is an md5sum of the prefix uuid, method, and $request
      local cache_key1 = res.headers["X-Cache-Key"]
      assert.matches("^[%w%d]+$", cache_key1)
      assert.equals(32, #cache_key1)

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-1.com",
        }
      })

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
          host = "api-6.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-6.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- give ourselves time to expire
      ngx.sleep(3)

      -- and go through the cycle again
      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-6.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-6.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- examine the behavior of keeping cache in memory for longer than ttl
      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-9.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-9.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- give ourselves time to expire
      ngx.sleep(3)

      -- and go through the cycle again
      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-9.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Refresh", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-9.com",
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
          host = "api-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/cache/2",
        headers = {
          host = "api-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- give ourselves time to expire
      ngx.sleep(3)

      -- and go through the cycle again
      res = assert(client:send {
        method = "GET",
        path = "/cache/2",
        headers = {
          host = "api-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/cache/2",
        headers = {
          host = "api-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- assert that max-age=0 never results in caching
      res = assert(client:send {
        method = "GET",
        path = "/cache/0",
        headers = {
          host = "api-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Bypass", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/cache/0",
        headers = {
          host = "api-7.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Bypass", res.headers["X-Cache-Status"])
    end)

    describe("respects cache-control", function()
      it("min-fresh", function()
        -- bypass via unsatisfied min-fresh
        local res = assert(client:send {
          method = "GET",
          path = "/cache/2",
          headers = {
            host = "api-7.com",
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
            host = "api-7.com",
            ["Cache-Control"] = "max-age=2"
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        res = assert(client:send {
          method = "GET",
          path = "/cache/10",
          headers = {
            host = "api-7.com",
            ["Cache-Control"] = "max-age=2"
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

        ngx.sleep(3)

        res = assert(client:send {
          method = "GET",
          path = "/cache/10",
          headers = {
            host = "api-7.com",
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
            host = "api-8.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        res = assert(client:send {
          method = "GET",
          path = "/cache/2",
          headers = {
            host = "api-8.com",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

        ngx.sleep(4)

        res = assert(client:send {
          method = "GET",
          path = "/cache/2",
          headers = {
            host = "api-8.com",
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
            host = "api-8.com",
            ["Cache-Control"] = "only-if-cached",
          }
        })

        assert.res_status(504, res)
      end)
    end)

    it("caches a streaming request", function()
      local res = assert(client:send {
        method = "GET",
        path = "/stream/5",
        headers = {
          host = "api-1.com",
        }
      })

      local body1 = assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
      assert.is_nil(res.headers["Content-Length"])

      res = assert(client:send {
        method = "GET",
        path = "/stream/5",
        headers = {
          host = "api-1.com",
        }
      })

      local body2 = assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      -- transfer-encoding is a hop-by-hop header. we may not have seen a
      -- content length last time, but Kong will always set Content-Length
      -- when delivering the response
      assert.is_not_nil(res.headers["Content-Length"])

      assert.same(body1, body2)
    end)

    it("uses an separate cache key betweens apis as a global plugin", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-3.com",
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
          host = "api-4.com",
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
          host = "api-2.com",
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
          host = "api-2.com",
        }
      })

      assert.res_status(200, res)

      assert.same("Hit", res.headers["X-Cache-Status"])
      local cache_key2 = res.headers["X-Cache-Key"]
      assert.same(cache_key1, cache_key2)

      assert.not_same(cache_key, cache_key1)
    end)

    it("uses request params as part of the cache key", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get?a=b&b=c",
        headers = {
          host = "api-1.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get?a=c",
        headers = {
          host = "api-1.com",
        }
      })

      assert.res_status(200, res)

      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get?b=c&a=b",
        headers = {
          host = "api-1.com",
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
          host = "api-12.com",
        }
      })

      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get?b=d&foo=b",
        headers = {
          host = "api-12.com",
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
          host = "api-11.com",
          foo = "bar"
        }
      })
      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-11.com",
          foo = "bar"
        }
      })
      assert.res_status(200, res)
      assert.same("Hit", res.headers["X-Cache-Status"])

      res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          host = "api-11.com",
          foo = "baz"
        }
      })
      assert.res_status(200, res)
      assert.same("Miss", res.headers["X-Cache-Status"])
    end)

    describe("handles authenticated apis", function()
      it("by ignoring cache if the request is unauthenticated", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "api-5.com",
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
            host = "api-5.com",
            apikey = "bob",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "api-5.com",
            apikey = "bob",
          }
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "api-5.com",
            apikey = "alice",
          }
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "api-5.com",
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
            host = "api-1.com",
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
            host = "api-1.com",
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
            host = "api-1.com",
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
            host = "api-10.com",
            ["Content-Type"] = "application/json",
          },
          {
            foo = "bar",
          },
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        res = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "api-10.com",
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
          path = "/status/418",
          headers = {
            host = "api-10.com",
          },
        })

        assert.res_status(418, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        res = assert(client:send {
          method = "GET",
          path = "/status/418",
          headers = {
            host = "api-10.com",
          },
        })

        assert.res_status(418, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
      end)

    end)

    describe("cache versioning", function()
      local cache_key

      setup(function()
        local strategy = require("kong.plugins.proxy-cache.strategies")({
          strategy_name = policy,
          strategy_opts = policy_config,
        })

        -- busta rhyme? not today. just busta cache
        strategy:flush(true)

        -- prime the cache and mangle its versioning
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "api-1.com",
          }
        })

        local body1 = assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        cache_key = res.headers["X-Cache-Key"]

        local cache = strategy:fetch(cache_key) or {}
        cache.version = "yolo"
        strategy:store(cache_key, cache, 10)
      end)

      local name = "bypasses old cache version data"
      if policy == "memory" then
        name = "#flaky" .. name
      end
      it(name, function()
        local res = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "api-1.com",
          }
        })

        local body = assert.res_status(200, res)
        assert.same("Bypass", res.headers["X-Cache-Status"])

        local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
        assert.matches("[proxy-cache] cache format mismatch, purging " .. cache_key,
                       err_log, nil, true)
      end)
    end)

    describe("displays Kong core headers:", function()
      it("X-Kong-Proxy-Latency", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get?show-me=proxy-latency",
          headers = {
            host = "api-1.com",
          }
        })

        local body = assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        assert.matches("^%d+$", res.headers["X-Kong-Proxy-Latency"])

        res = assert(client:send {
          method = "GET",
          path = "/get?show-me=proxy-latency",
          headers = {
            host = "api-1.com",
          }
        })

        local body = assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        assert.matches("^%d+$", res.headers["X-Kong-Proxy-Latency"])
        if policy == "memory" then
          assert.equals(0, tonumber(res.headers["X-Kong-Proxy-Latency"]))
        else
          assert.matches("^%d+$", res.headers["X-Kong-Proxy-Latency"])
        end
      end)

      it("X-Kong-Upstream-Latency", function()
        local res = assert(client:send {
          method = "GET",
          path = "/get?show-me=upstream-latency",
          headers = {
            host = "api-1.com",
          }
        })

        local body = assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        assert.matches("^%d+$", res.headers["X-Kong-Upstream-Latency"])

        res = assert(client:send {
          method = "GET",
          path = "/get?show-me=upstream-latency",
          headers = {
            host = "api-1.com",
          }
        })

        local body = assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        assert.matches("^%d+$", res.headers["X-Kong-Upstream-Latency"])
        assert.equals(0, tonumber(res.headers["X-Kong-Upstream-Latency"]))
      end)
    end)
  end)
end
