-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local pl_file = require "pl.file"
local plugin_strategies = require "kong.plugins.graphql-proxy-cache-advanced.strategies"
local cjson   = require "cjson"

local TIMEOUT = 10 -- default timeout for non-memory strategies


local REDIS_HOST = helpers.redis_host
local REDIS_PORT = helpers.redis_port or 6379
local REDIS_SSL_PORT = helpers.redis_ssl_port or 6380
local REDIS_SSL_SNI = helpers.redis_ssl_sni
local REDIS_CLUSTER_ADDRESSES = ee_helpers.parsed_redis_cluster_addresses()
local REDIS_DATABASE = 1

local all_strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy
local strategies = require("kong.plugins.proxy-cache-advanced.strategies")


for _, strategy in all_strategies() do
  for _, policy in ipairs({"memory", "redis"}) do
    describe("graphql-proxy-cache-advanced access with strategy #" .. strategy .. " and policy #" .. policy, function()
      local client, admin_client
      local policy_config

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

      local plugin_strategy = plugin_strategies({
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
            path   = "/graphql-proxy-cache-advanced/" .. key
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

      local db_strategy = strategy ~= "off" and strategy or nil

      local bp
      setup(function()
        bp = helpers.get_db_utils(db_strategy, nil, {"graphql-proxy-cache-advanced"})
        plugin_strategy:flush(true)

        local route1 = assert(bp.routes:insert {
          hosts = { "route-1.test" },
        })

        local route2 = assert(bp.routes:insert {
          hosts = { "route-2.test" },
        })

        local route3 = assert(bp.routes:insert {
          hosts = { "route-3.test" },
        })

        local route4 = assert(bp.routes:insert {
          hosts = { "route-4.test" },
        })

        local route5 = assert(bp.routes:insert {
          hosts = { "route-5.test" },
        })

        local route6 = assert(bp.routes:insert {
          hosts = { "route-6.test" },
        })

        assert(bp.plugins:insert {
          name = "graphql-proxy-cache-advanced",
          route = { id = route1.id },
          config = {
            strategy = policy,
            [policy] = policy_config,
          },
        })

        assert(bp.plugins:insert {
          name = "graphql-proxy-cache-advanced",
          route = { id = route2.id },
          config = {
            strategy = policy,
            cache_ttl = 2,
            [policy] = policy_config,
          },
        })

        assert(bp.plugins:insert {
          name = "graphql-proxy-cache-advanced",
          route = { id = route3.id },
          config = {
            strategy = policy,
            cache_ttl = 2,
            [policy] = policy_config,
          },
        })

        assert(bp.plugins:insert {
          name = "graphql-proxy-cache-advanced",
          route = { id = route4.id },
          config = {
            strategy = policy,
            [policy] = policy_config,
          },
        })

        assert(bp.plugins:insert {
          name = "graphql-proxy-cache-advanced",
          route = { id = route5.id },
          config = {
            strategy = policy,
            [policy] = policy_config,
          },
        })

        assert(bp.plugins:insert {
          name = "graphql-proxy-cache-advanced",
          route = { id = route6.id },
          config = {
            strategy = policy,
            [policy] = policy_config,
            vary_headers = {"foo"}
          },
        })

        assert(helpers.start_kong({
          database = db_strategy,
          plugins = "bundled,graphql-proxy-cache-advanced",
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

        helpers.stop_kong()
      end)

      it("caches a simple request", function()
        local res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-1.test",
          },
          body = '{ query { user(id:"1") { id, name }}}'
        })

        local body1 = assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        -- cache key is a sha256sum of the prefix uuid, method, and $request
        local cache_key1 = res.headers["X-Cache-Key"]
        assert.matches("^[%w%d]+$", cache_key1)
        assert.equals(64, #cache_key1)

        wait_until_key_in_cache(cache_key1)
        --
        res = client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-1.test",
          },
          body = '{ query { user(id:"1") { id, name }}}'
        }

        local body2 = assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        local cache_key2 = res.headers["X-Cache-Key"]
        assert.same(cache_key1, cache_key2)

        -- assert that response bodies are identical
        assert.same(body1, body2)
      end)

      it("differentiate two same structure queries with different filter parameters", function()
        local res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-4.test",
          },
          body = '{ query { user(id:"1") { id, name }}}'
        })

        local body1 = assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        -- cache key is a sha256sum of the prefix uuid, method, and $request
        local cache_key1 = res.headers["X-Cache-Key"]
        assert.matches("^[%w%d]+$", cache_key1)
        assert.equals(64, #cache_key1)

        wait_until_key_in_cache(cache_key1)
        --
        res = client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-4.test",
          },
          body = '{ query { user(id:"1") { id, name }}}'
        }

        local body2 = assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        local cache_key2 = res.headers["X-Cache-Key"]
        assert.same(cache_key1, cache_key2)

        -- assert that response bodies are identical
        assert.same(body1, body2)

        res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-4.test",
          },
          body = '{ query { user(id:"1-2") { id, name }}}'
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
      end)

      it("differentiate two same queries with extra node parameter", function()
        local res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-5.test",
          },
          body = '{ query { user(id:"5") { id, name }}}'
        })

        local body1 = assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        -- cache key is a sha256sum of the prefix uuid, method, and $request
        local cache_key1 = res.headers["X-Cache-Key"]
        assert.matches("^[%w%d]+$", cache_key1)
        assert.equals(64, #cache_key1)

        wait_until_key_in_cache(cache_key1)
        --
        res = client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-5.test",
          },
          body = '{ query { user(id:"5") { id, name }}}'
        }

        local body2 = assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        local cache_key2 = res.headers["X-Cache-Key"]
        assert.same(cache_key1, cache_key2)

        -- assert that response bodies are identical
        assert.same(body1, body2)

        res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-5.test",
          },
          body = '{ query { user(id:"5") { id, name, surname }}}'
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
      end)

      it("respects cache ttl", function()
        local res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-2.test",
          },
          body = '{ query { user(id:"2") { id, name }}}'
        })

        local cache_key2 = res.headers["X-Cache-Key"]
        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])

        wait_until_key_in_cache(cache_key2)

        res = client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-2.test",
          },
          body = '{ query { user(id:"2") { id, name }}}'
        }

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        local cache_key = res.headers["X-Cache-Key"]

        -- wait until the strategy expires the object for the given
        -- cache key
        wait_until_key_not_in_cache(cache_key)

        -- and go through the cycle again
        res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-2.test",
          },
          body = '{ query { user(id:"2") { id, name }}}'
        })

        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-2.test",
          },
          body = '{ query { user(id:"2") { id, name }}}'
        })

        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
      end)

      it("uses headers if instructed to do so", function()
        local res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-6.test",
            foo = "bar"
          },
          body = '{ query { user(id:"2") { id, name }}}'
        })
        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
        local cache_key = res.headers["X-Cache-Key"]

        -- wait until the underlying strategy converges
        wait_until_key_in_cache(cache_key)

        res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-6.test",
            foo = "bar"
          },
          body = '{ query { user(id:"2") { id, name }}}'
        })
        assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])

        res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-6.test",
            foo = "baz"
          },
          body = '{ query { user(id:"2") { id, name }}}'
        })
        assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
      end)

      describe("cache versioning", function()
        local cache_key
  
        -- This test tries to flush the proxy-cache from the test
        -- code. This is is doable in the redis strategy as it can be
        -- referenced (and flushed) from test code. nginx's in-memory
        -- cache can't be referenced from test code.
        local test_except_memory = policy == "memory" and pending or it
        test_except_memory("bypasses old cache version data", function()
          plugin_strategy:flush(true)

          -- prime the cache and mangle its versioning
          local res = assert(client:send {
            method = "POST",
            path = "/request",
            headers = {
              host = "route-1.test",
            },
            body = '{ query { user(id:"1") { id, name }}}'
          })
  
          assert.res_status(200, res)
          assert.same("Miss", res.headers["X-Cache-Status"])
          cache_key = res.headers["X-Cache-Key"]
  
          -- wait until the underlying strategy converges
          wait_until_key_in_cache(cache_key)
  
          local cache = plugin_strategy:fetch(cache_key) or {}
          cache.version = "yolo"
          plugin_strategy:store(cache_key, cache, 10)
  
          local res = assert(client:send {
            method = "POST",
            path = "/request",
            headers = {
              host = "route-1.test",
            },
            body = '{ query { user(id:"1") { id, name }}}'
          })
  
          assert.res_status(200, res)
          assert.same("Bypass", res.headers["X-Cache-Status"])
  
          local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
          assert.matches("[graphql-proxy-cache-advanced] cache format mismatch, purging " .. cache_key,
                         err_log, nil, true)
        end)
      end)

      if policy == "redis" then
        describe("redis cluster", function()
          lazy_setup(function()
            local redis_cluster_policy_config = {
              cluster_addresses = REDIS_CLUSTER_ADDRESSES,
              keepalive_pool_size = 30,
              keepalive_backlog = 30,
              ssl = false,
              ssl_verify = false,
              database = REDIS_DATABASE,
            }

            local redis_cluster_strategy = strategies({
              strategy_name = policy,
              strategy_opts = redis_cluster_policy_config,
            })

            redis_cluster_strategy:flush(true)

            local route17 = assert(bp.routes:insert({
              hosts = { "route-17.test" },
            }))

            assert(bp.plugins:insert {
              name = "graphql-proxy-cache-advanced",
              route = { id = route17.id },
              config = {
                strategy = policy,
                [policy] = redis_cluster_policy_config,
              },
            })

            assert(helpers.restart_kong({
              plugins = "bundled,graphql-proxy-cache-advanced",
              nginx_conf = "spec/fixtures/custom_nginx.template",
            }))
          end)

          it("returns 200 OK", function()
            local res = assert(client:send {
              method = "POST",
              path = "/request",
              headers = {
                host = "route-17.test",
              },
              body = '{ query { user(id:"1") { id, name }}}'
            })

            local body1 = assert.res_status(200, res)
            assert.same("Miss", res.headers["X-Cache-Status"])

            local cache_key1 = res.headers["X-Cache-Key"]
            assert.matches("^[%w%d]+$", cache_key1)
            assert.equals(64, #cache_key1)

            wait_until_key_in_cache(cache_key1)

            local res = client:send {
              method = "POST",
              path = "/request",
              headers = {
                host = "route-17.test",
              },
              body = '{ query { user(id:"1") { id, name }}}'
            }

            local body2 = assert.res_status(200, res)
            assert.same("Hit", res.headers["X-Cache-Status"])
            local cache_key2 = res.headers["X-Cache-Key"]
            assert.same(cache_key1, cache_key2)

            assert.same(body1, body2)
          end)
        end)

        describe("some broken redis config", function()
          local route_bypass, route_no_bypass
  
          setup(function()
            -- Best website ever
            route_bypass = assert(bp.routes:insert {
              hosts = { "broken-redis-bypass.test" }
            })
  
            route_no_bypass = assert(bp.routes:insert {
              hosts = { "broken-redis-no-bypass.test" }
            })
  
            local route_ssl_no_bypass = assert(bp.routes:insert {
              hosts = { "broken-ssl-redis-no-bypass.test" }
            })
  
            local broken_config = {
              host = "yolo",
              port = REDIS_PORT,
              database = REDIS_DATABASE,
            }
  
            local broken_ssl_config = {
              host = REDIS_HOST,
              port = REDIS_SSL_PORT,
              ssl = false,
              ssl_verify = false,
              server_name = REDIS_SSL_SNI,
              database = REDIS_DATABASE,
            }
  
            assert(bp.plugins:insert {
              name = "graphql-proxy-cache-advanced",
              route = { id = route_bypass.id },
              config = {
                strategy = policy,
                [policy] = broken_config,
                bypass_on_err = true,
              },
            })
  
            assert(bp.plugins:insert {
              name = "graphql-proxy-cache-advanced",
              route = { id = route_no_bypass.id },
              config = {
                strategy = policy,
                [policy] = broken_config,
                bypass_on_err = false,
              },
            })
  
            assert(bp.plugins:insert {
              name = "graphql-proxy-cache-advanced",
              route = { id = route_ssl_no_bypass.id },
              config = {
                strategy = policy,
                [policy] = broken_ssl_config,
                bypass_on_err = false,
              },
            })
  
            -- Force kong to reload router
            assert(helpers.restart_kong({
              plugins = "bundled,graphql-proxy-cache-advanced",
              nginx_conf = "spec/fixtures/custom_nginx.template",
            }))
          end)
  
          it("bypasses cache when bypass_on_err is enabled", function()
            local res = assert(client:send {
              method = "POST",
              path = "/request",
              headers = {
                host = "broken-redis-bypass.test",
              },
              body = '{ query { user(id:"1") { id, name }}}'
            })
            assert.res_status(200, res)
            assert.same("Bypass", res.headers["X-Cache-Status"])
          end)
          it("crashes when bypass_on_err is disabled", function()
            local res = assert(client:send {
              method = "POST",
              path = "/request",
              headers = {
                host = "broken-redis-no-bypass.test",
              },
              body = '{ query { user(id:"1") { id, name }}}'
            })
            assert.res_status(502, res)
          end)

          it("crashes when ssl is false and bypass_on_err is disabled", function()
            local res = assert(client:send {
              method = "POST",
              path = "/request",
              headers = {
                host = "broken-ssl-redis-no-bypass.test",
              },
              body = '{ query { user(id:"1") { id, name }}}'
            })
            local body = assert.res_status(502, res)
            local json_body = cjson.decode(body)
            assert.same({
              message = "closed",
            }, json_body)
          end)
        end)
      end
    end)

    describe("graphql-proxy-cache-advanced works with vitals prometheus strategy: #mydescribe", function()
      local bp
      local client, admin_client
      local policy_config
  
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
  
      local function wait_until_key(key, func)
        helpers.wait_until(function()
          local res = admin_client:send {
            method = "GET",
            path   = "/graphql-proxy-cache-advanced/" .. key
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
  
      setup(function()
        bp = helpers.get_db_utils(nil, nil, {"graphql-proxy-cache-advanced"})
        strategy:flush(true)
  
        local route_vitals = assert(bp.routes:insert {
          hosts = { "route-vitals.test" },
        })
  
        assert(bp.plugins:insert {
          name = "graphql-proxy-cache-advanced",
          route = { id = route_vitals.id },
          config = {
            strategy = policy,
            [policy] = policy_config,},
        })
  
        helpers.start_kong({
          plugins = "bundled,graphql-proxy-cache-advanced",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          vitals = "on",
          vitals_strategy = "prometheus",
          vitals_tsdb_address = "127.0.0.1:9090",
          vitals_statsd_address = "127.0.0.1:8125",
        }, nil, false)
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
  
        helpers.stop_kong()
      end)
  
      it("caches a simple request", function()
        local res = assert(client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-vitals.test",
          }
        })
  
        local body1 = assert.res_status(200, res)
        assert.same("Miss", res.headers["X-Cache-Status"])
  
        -- cache key is a sha256sum of the prefix uuid, method, and $request
        local cache_key1 = res.headers["X-Cache-Key"]
        assert.matches("^[%w%d]+$", cache_key1)
        assert.equals(64, #cache_key1)
  
        wait_until_key_in_cache(cache_key1)
  
        local res = client:send {
          method = "POST",
          path = "/request",
          headers = {
            host = "route-vitals.test",
          }
        }
  
        local body2 = assert.res_status(200, res)
        assert.same("Hit", res.headers["X-Cache-Status"])
        local cache_key2 = res.headers["X-Cache-Key"]
        assert.same(cache_key1, cache_key2)
  
        -- assert that response bodies are identical
        assert.same(body1, body2)
      end)
  
    end)
  end
end
