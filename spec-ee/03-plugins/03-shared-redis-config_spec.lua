-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local redis_helper = require "spec.helpers.redis_helper"
local redis_cluster = require "resty.rediscluster"
local ee_helpers = require "spec-ee.helpers"

local REDIS_HOST = helpers.redis_host
local REDIS_PORT = helpers.redis_port

local TEST_HEADER_NAME = "X-TEST-HADER"
local REDIS_KEY = "test-key"

for _, strategy in helpers.each_strategy() do
  describe("Test plugin `redis-user`: [#" .. strategy .. "]", function()
    local admin_client, proxy_client, bp, route1, route2, route3, route4, route5, redis_client

    lazy_setup(function()
      helpers.test_conf.lua_package_path = helpers.test_conf.lua_package_path .. ";./spec-ee/fixtures/custom_plugins/?.lua"
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, { 'reconfiguration-completion', 'redis-user' })

      route1 = bp.routes:insert {
        hosts = { "test1-single.test" },
      }

      route2 = bp.routes:insert {
        hosts = { "test2-cluster.test" },
      }

      route3 = bp.routes:insert {
        hosts = { "test3-cluster.test" },
      }

      route4 = bp.routes:insert {
        hosts = { "test4-sentinel.test" },
      }

      route5 = bp.routes:insert {
        hosts = { "test5-sentinel.test" },
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,reconfiguration-completion,redis-user",
        lua_package_path  = "?./spec-ee/fixtures/custom_plugins/?.lua",
      }))

      proxy_client, admin_client = helpers.make_synchronized_clients()
    end)

    before_each(function()
      helpers.clean_logfile()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("normal - single redis instance", function()
      lazy_setup(function()
        redis_client = redis_helper.connect(REDIS_HOST, REDIS_PORT)
      end)

      before_each(function()
        redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)
      end)

      after_each(function()
        redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)
      end)

      it("allows creating plugin and connects to redis", function()
        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/plugins",
          body    = {
            name  = "redis-user",
            route = { id = route1.id },
            config = {
              header_name = TEST_HEADER_NAME,
              redis_key = REDIS_KEY,
              redis = {
                host = REDIS_HOST,
                port = REDIS_PORT
              }
            },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/request",
          headers = {
            ["Host"]   = "test1-single.test",
            [TEST_HEADER_NAME] = "value-to-set"
          }
        })

        assert.res_status(200, res)

        local ok, err = redis_client:get(REDIS_KEY)
        assert.same("value-to-set", ok)
        assert.falsy(err)
      end)
    end)

    describe("redis cluster", function()
      local redis_cluster_client
      lazy_setup(function()
        local redis_cluster_config = {
          dict_name = "kong_locks",               --shared dictionary name for locks, if default value is not used
          name = "testCluster",                   --rediscluster name
          serv_list = ee_helpers.redis_cluster_nodes,
        }

        redis_cluster_client = assert(redis_cluster:new(redis_cluster_config))
      end)

      before_each(function()
        redis_cluster_client:flushall()
      end)

      after_each(function()
        redis_cluster_client:flushall()
      end)

      describe("deprecated configuration", function()
        it("allows creating plugin and translates old values to new ones", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "redis-user",
              route = { id = route2.id },
              config = {
                header_name = TEST_HEADER_NAME,
                redis_key = REDIS_KEY,
                redis = {
                  cluster_addresses = ee_helpers.redis_cluster_addresses
                }
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.logfile().has.line("cluster_addresses is deprecated, please use cluster_nodes instead (deprecated after 4.0)", true)

          local length = 0
          for _, _ in pairs(json.config.redis.cluster_addresses) do length = length + 1 end
          assert.truthy(length > 0) -- just to make sure we are not testing empty arrays

          assert.same(ee_helpers.redis_cluster_nodes, json.config.redis.cluster_nodes)
          assert.same(ee_helpers.redis_cluster_addresses, json.config.redis.cluster_addresses)

          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              ["Host"]   = "test2-cluster.test",
              [TEST_HEADER_NAME] = "value-to-set"
            }
          })

          assert.res_status(200, res)

          local ok, err = redis_cluster_client:get(REDIS_KEY)
          assert.same("value-to-set", ok)
          assert.falsy(err)
        end)
      end)

      describe("new configuration", function()
        it("allows creating plugin and uses new values", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "redis-user",
              route = { id = route3.id },
              config = {
                header_name = TEST_HEADER_NAME,
                redis_key = REDIS_KEY,
                redis = {
                  cluster_nodes = ee_helpers.redis_cluster_nodes
                }
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.logfile().has.no.line("cluster_addresses is deprecated, please use cluster_nodes instead (deprecated after 4.0)", true)

          local length = 0
          for _, _ in pairs(json.config.redis.cluster_addresses) do length = length + 1 end
          assert.truthy(length > 0) -- just to make sure we are not testing empty arrays

          assert.same(ee_helpers.redis_cluster_nodes, json.config.redis.cluster_nodes)
          assert.same(ee_helpers.redis_cluster_addresses, json.config.redis.cluster_addresses)

          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              ["Host"]   = "test3-cluster.test",
              [TEST_HEADER_NAME] = "value-to-set"
            }
          })

          assert.res_status(200, res)

          local ok, err = redis_cluster_client:get(REDIS_KEY)
          assert.same("value-to-set", ok)
          assert.falsy(err)
        end)
      end)
    end)

    describe("redis sentinel", function()
      lazy_setup(function()
        redis_client = redis_helper.connect(REDIS_HOST, REDIS_PORT)
      end)

      before_each(function()
        redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)
      end)

      after_each(function()
        redis_helper.reset_redis(REDIS_HOST, REDIS_PORT)
      end)

      describe("deprecated configuration", function()
        it("allows creating plugin and translates old values to new ones", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "redis-user",
              route = { id = route4.id },
              config = {
                header_name = TEST_HEADER_NAME,
                redis_key = REDIS_KEY,
                redis = {
                  sentinel_addresses = { REDIS_HOST .. ":" .. REDIS_PORT },
                  sentinel_master = "mymaster",
                  sentinel_role = "master"
                }
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.logfile().has.line("sentinel_addresses is deprecated, please use sentinel_nodes instead (deprecated after 4.0)", true)

          assert.same({REDIS_HOST .. ":" .. REDIS_PORT}, json.config.redis.sentinel_addresses)
          assert.same({ {
            host = REDIS_HOST,
            port = REDIS_PORT
          }}, json.config.redis.sentinel_nodes)

          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              ["Host"]   = "test4-sentinel.test",
            }
          })

          -- redis sentinel is not enabled in tests so the proxy path will fail on connection
          -- we check here if the returned error is from executing sentinel path on lua-resty-redis-connector lib
          local body = assert.res_status(500, res)
          assert(body:find("ERR unknown command 'sentinel'"))
        end)
      end)

      describe("new configuration", function()
        it("allows creating plugin and uses new values", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "redis-user",
              route = { id = route5.id },
              config = {
                header_name = TEST_HEADER_NAME,
                redis_key = REDIS_KEY,
                redis = {
                  sentinel_nodes = { {
                    host = REDIS_HOST,
                    port = REDIS_PORT
                  } },
                  sentinel_master = "mymaster",
                  sentinel_role = "master"
                }
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.logfile().has.no.line("sentinel_addresses is deprecated, please use sentinel_nodes instead (deprecated after 4.0)", true)

          assert.same({REDIS_HOST .. ":" .. REDIS_PORT}, json.config.redis.sentinel_addresses)
          assert.same({ {
            host = REDIS_HOST,
            port = REDIS_PORT
          }}, json.config.redis.sentinel_nodes)

          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/request",
            headers = {
              ["Host"]   = "test5-sentinel.test",
            }
          })

          -- redis sentinel is not enabled in tests so the proxy path will fail on connection
          -- we check here if the returned error is from executing sentinel path on lua-resty-redis-connector lib
          local body = assert.res_status(500, res)
          assert(body:find("ERR unknown command 'sentinel'"))
        end)
      end)
    end)
  end)
end
