-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local cjson = require "cjson"
local redis_helper = require "spec.helpers.redis_helper"


local HTTP_SERVER_PORT_16 = helpers.get_available_port()
local HTTP_SERVER_PORT = helpers.get_available_port()
local PROXY_PORT = helpers.get_available_port()
local REDIS_HOST = helpers.redis_host
local REDIS_PORT = helpers.redis_port or 6379
local REDIS_DATABASE = 1

local REDIS_USERNAME_VALID = "sp-user"
local REDIS_PASSWORD_VALID = "sp-pass"

local floor = math.floor
local time = ngx.time
local ngx_sleep = ngx.sleep
local update_time  = ngx.update_time

-- all_strategries is not available on earlier versions spec.helpers in Kong
local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

-- helper functions to build test objects
local function build_request(host, path, method)
  return {
    method = method or "GET",
    path = path,
    headers = {
      ["Host"] = host
    }
  }
end

local function build_plugin_fn(strategy)
  return function (service_id, windows, limits, sync_rate, retry_jitter, hide_headers, redis_configuration, extra_conf)
    if type(windows) ~= "table" then
      windows = { windows }
    end
    if type(limits) ~= "table" then
      limits = { limits }
    end
    local conf = {
      strategy = strategy,
      window_size = windows,
      limit = limits,
      sync_rate = (strategy ~= "local" and (sync_rate or 0) or -1),
      retry_after_jitter_max = retry_jitter,
      hide_client_headers = hide_headers,
      redis = redis_configuration,
    }
    if extra_conf then
      for key, value in pairs(extra_conf) do
        conf[key] = value
      end
    end
    return {
      name = "service-protection",
      service = { id = service_id },
      config = conf
    }
  end
end

local function redis_test_configurations(policy)
  local redis_configurations = {
    no_acl =  {
      host = REDIS_HOST,
      port = REDIS_PORT,
      database = REDIS_DATABASE,
      username = nil,
      password = nil,
    },
  }

  if policy == "redis" then
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


-- align the time to the begining of a fixed window
-- so that we are less likely to encounter a window reset
-- during the test
local function wait_for_next_fixed_window(window_size)
  local window_start = floor(time() / window_size) * window_size
  local window_elapsed_time = (time() - window_start)
  if window_elapsed_time > (window_size / 2) then
    ngx_sleep(window_size - window_elapsed_time)
    window_start = window_start + window_size
  end
  return window_start
end

for _, strategy in strategies() do
  local policy = strategy == "off" and "redis" or "local"
  local MOCK_RATE = 3
  local MOCK_ORIGINAL_LIMIT = 6

  local base = "service-protection [#"..strategy.."]"

  -- helper function to build plugin config
  local build_plugin = build_plugin_fn(policy)

  for redis_description, redis_configuration in pairs(redis_test_configurations(policy)) do
    local s = base
    if policy == "redis" then
      s = s .. " [#" .. redis_description .. "]"
    end
    describe(s, function()
      local bp, consumer, plugin1, plugin2, plugin3, plugin4
      local proxy_client
      local redis_client

      lazy_setup(function()
        if policy == "redis" then
          redis_client = redis_helper.connect(REDIS_HOST, REDIS_PORT)
          redis_client:flush_all()
          redis_helper.add_admin_user(redis_client, REDIS_USERNAME_VALID, REDIS_PASSWORD_VALID)
        end

        bp = helpers.get_db_utils(strategy ~= "off" and strategy or nil,
                                  nil,
                                  {"service-protection", "exit-transformer"})

        consumer = assert(bp.consumers:insert {
          custom_id = "provider_124"
        })

        if strategy ~= "off" then
          local service24 = assert(bp.services:insert())

          local route24 = assert(bp.routes:insert {
            name = "route-24",
            service = { id = service24.id },
            hosts = { "test24.com" },
          })

          assert(bp.plugins:insert {
            name = "key-auth",
            route = { id = route24.id },
          })

          assert(bp.plugins:insert {
            name = "service-protection",
            service = { id = service24.id },
            config = {
              strategy = policy,
              window_size = { 5 },
              limit = { 5 },
              sync_rate = (policy ~= "local" and 1 or nil),
              redis = redis_configuration,
            }
          })

        end

        assert(bp.keyauth_credentials:insert {
          key = "apikey123",
          consumer = { id = consumer.id },
        })

        local service1 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-1",
          service = { id = service1.id },
          hosts = { "test1.test" },
          paths = { "/" },
        })
        assert(bp.plugins:insert(
          build_plugin(service1.id, MOCK_RATE, 6, 10, nil, nil, redis_configuration)
        ))

        local service2 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-2",
          service = { id = service2.id },
          hosts = { "test2.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(service2.id, { 5, 10 }, { 3, 5 }, 10, nil, nil, redis_configuration)
        ))

        local service3 = assert(bp.services:insert())
        local route3 = assert(bp.routes:insert {
          name = "route-3",
          service = { id = service3.id },
          hosts = { "test3.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route3.id },
        })
        assert(bp.plugins:insert(
          build_plugin(
            service3.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration
          )
        ))
        local service4 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-4",
          service = { id = service4.id },
          hosts = { "test4.test" },
          paths = { "/share_ns_foo" }
        })
        assert(bp.plugins:insert(
          build_plugin(
            service4.id, MOCK_RATE, 3, 10, nil,
            nil, redis_configuration, { namespace = "foo" }
          )
        ))

        local service5 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-5",
          service = { id = service5.id },
          hosts = { "test5.test" },
          paths = { "/share_ns_foo" }
        })
        assert(bp.plugins:insert(
          build_plugin(
            service5.id, MOCK_RATE, 3, 10, nil,
            nil, redis_configuration, { namespace = "foo" }
          )
        ))

        local service6 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-6",
          service = { id = service6.id },
          hosts = { "test6.test" },
        })
        plugin3 = assert(bp.plugins:insert(
          build_plugin(
            service6.id, 5, 2, 2, nil,
            nil, redis_configuration,
            { window_type = "fixed", retry_after_jitter_max = nil }
          )
        ))

        local service7 = assert(bp.services:insert())
        local route7 = assert(bp.routes:insert {
          name = "route-7",
          service = { id = service7.id },
          hosts = { "test7.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route7.id },
        })
        assert(bp.plugins:insert(
          build_plugin(
            service7.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration
          )
        ))

        local service8 = assert(bp.services:insert())
        local route8 = assert(bp.routes:insert {
          name = "route-8",
          service = { id = service8.id },
          hosts = { "test8.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route8.id },
        })
        assert(bp.plugins:insert(
          build_plugin(
            service8.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration
          )
        ))

        local service9 = assert(bp.services:insert {
          host = "test9.test",
        })
        assert(bp.routes:insert {
          name = "route-9",
          service = { id = service9.id },
          hosts = { "test9.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(
            service9.id, MOCK_RATE, 1, 10, nil,
            true, redis_configuration, { window_type = "fixed" }
          )
        ))

        local service10 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-10",
          service = { id = service10.id },
          hosts = { "test10.test" },
        })

        assert(bp.plugins:insert(
          build_plugin(
            service10.id, 10, 6, 10, nil,
            nil, redis_configuration,
            { window_type = "fixed"}
          )
        ))

        local service11 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-11",
          service = { id = service11.id },
          hosts = { "test11.test" },
        })

        assert(bp.plugins:insert(
          build_plugin(
            service11.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration,
            { window_type = "fixed" }
          )
        ))

        local service12 = assert(bp.services:insert())
        local route12 = assert(bp.routes:insert {
          name = "route-12",
          service = { id = service12.id },
          hosts = { "test12.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route12.id },
        })
        assert(bp.plugins:insert(
          build_plugin(
            service12.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration
          )
        ))

        local service13 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "test-13",
          service = { id = service13.id },
          hosts = { "test13.test" },
        })
        assert(bp.plugins:insert(build_plugin(service13.id, MOCK_RATE, 2, 0, 5, false, redis_configuration)))

        local service14 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "test-14",
          service = { id = service14.id },
          hosts = { "test14.test" },
        })
        assert(bp.plugins:insert(build_plugin(service14.id, MOCK_RATE, 2, 0, 5, true, redis_configuration)))

        -- Shared service with multiple routes
        local shared_service = bp.services:insert {
          name = "shared-test-service",
        }
        assert(bp.routes:insert {
          name = "shared-service-route-1",
          hosts = { "shared-service-test-1.test" },
          service = { id = shared_service.id },
        })
        assert(bp.routes:insert {
          name = "shared-service-route-2",
          hosts = { "shared-service-test-2.test" },
          service = { id = shared_service.id },
        })
        assert(bp.plugins:insert({
          name = "service-protection",
          service = { id = shared_service.id },
          config = {
            strategy = policy,
            window_size = { 10 },
            window_type = "fixed",
            limit = { 6 },
            sync_rate = (policy ~= "local" and 0 or nil),
            redis = redis_configuration,
          },
        }))

        local service15 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "test-15",
          service = { id = service15.id },
          hosts = { "test15.test" },
        })
        plugin4 = assert(bp.plugins:insert(
          build_plugin_fn("redis")(
            service15.id, 5, 1, 0.1, nil,
            nil, redis_configuration,
            { namespace = "2D8851DEAC3D4FC5889CF03A9836948F", }
          )
        ))

        local service17 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "test-17",
          service = { id = service17.id },
          hosts = { "test17.test" },
        })
        plugin1 = assert(bp.plugins:insert(
          build_plugin_fn("cluster")(
            service17.id, 5, 6, 1, nil,
            nil, nil,
            { namespace = "Bk1krkTWBqmcKEQVW5cQNLgikuKygjnu" }
          )
        ))

        local service177 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "test-177",
          service = { id = service177.id },
          hosts = { "test177.test" },
        })
        plugin2 = assert(bp.plugins:insert(
          build_plugin_fn("cluster")(
            service177.id, 5, 6, 1, nil,
            nil, nil,
            { namespace = "046F4FC717A147C2A446A4BEA763CF1E" }
          )
        ))

        local service19 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "test-19",
          service = { id = service19.id },
          hosts = { "test19.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(
            service19.id, 5, 6, 1, nil,
            nil, redis_configuration
          )
        ))

        local service20 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "test-20",
          service = { id = service20.id },
          hosts = { "test20.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(
            service20.id, 10, 6, nil, nil,
            nil, redis_configuration
          )
        ))

        local service21 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-21",
          service = { id = service21.id },
          hosts = { "test21.test" },
        })

        assert(bp.plugins:insert {
          name = "service-protection",
          service = { id = service21.id },
          config = {
            strategy = policy,
            window_size = { 5 },
            limit = { 5 },
            sync_rate = (policy ~= "local" and 1 or nil),
            redis = redis_configuration,
            disable_penalty = true,
          }
        })

        local service22 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-22",
          service = { id = service22.id },
          hosts = { "test22.test" },
        })

        assert(bp.plugins:insert {
          name = "service-protection",
          service = { id = service22.id },
          config = {
            strategy = policy,
            window_size = { 5 },
            limit = { 5 },
            sync_rate = (policy ~= "local" and 1 or nil),
            redis = redis_configuration,
            -- disable_penalty = false,
          }
        })

        local service23 = assert(bp.services:insert {
          host = "test23.test",
        })
        local route23 = assert(bp.routes:insert {
          name = "route-23",
          service = { id = service23.id },
          hosts = { "test23.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route23.id },
        })
        assert(bp.plugins:insert(
          build_plugin(service23.id, MOCK_RATE, 3, 1, nil, nil, redis_configuration)
        ))

        local service_for_consumer_group = assert(bp.services:insert())
        local route_for_consumer_group = assert(bp.routes:insert {
          name = "test_consumer_groups",
          service = { id = service_for_consumer_group.id },
          hosts = { "testconsumergroup.test"},
        })

        local service_for_consumer_group_no_config = assert(bp.services:insert())
        local route_for_consumer_group_no_config = assert(bp.routes:insert {
          name = "test_consumer_groups_no_config",
          service = { id = service_for_consumer_group_no_config.id },
          hosts = { "testconsumergroupnoconfig.test"},
        })

        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route_for_consumer_group.id },
        })

        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route_for_consumer_group_no_config.id },
        })

        assert(bp.plugins:insert(
          build_plugin(
            service_for_consumer_group.id, 5, MOCK_ORIGINAL_LIMIT, 2, nil,
            nil, redis_configuration, {
              namespace = "Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu"
            }
          )
        ))

        assert(bp.plugins:insert(
          build_plugin(
            service_for_consumer_group_no_config.id, 5, MOCK_ORIGINAL_LIMIT, 2, nil,
            nil, redis_configuration, {
              namespace = "Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu"
            }
          )
        ))


        local service_for_custom_response = assert(bp.services:insert())
        assert(bp.routes:insert {
          hosts = { "route_for_custom_response.test" },
          service = { id = service_for_custom_response.id },
        })

        assert(bp.plugins:insert(
          build_plugin(
            service_for_custom_response.id, 5, MOCK_ORIGINAL_LIMIT, 2, nil,
            nil, redis_configuration, {
              error_code = 405,
              error_message = "Testing",
            }
          )
        ))

        -- This way when connecting to redis it always refused immediately
        -- to fail quickly, reducing the time consuming
        local invalid_redis_configuration = {
          host = "localhost",
          port = helpers.get_available_port(),
          database = REDIS_DATABASE,
          username = nil,
          password = nil,
        }
        local service26 = assert(bp.services:insert())
        assert(bp.routes:insert {
          name = "route-26",
          service = { id = service26.id },
          hosts = { "route-26.test" },
        })
        assert(bp.plugins:insert(
          build_plugin_fn("redis")(
            service26.id, 5, 3, 0, nil,
            nil, invalid_redis_configuration
          )
        ))

        assert(helpers.start_kong{
          plugins = "service-protection,key-auth,exit-transformer",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          database = strategy ~= "off" and strategy or nil,
          db_update_frequency = 0.1,
          prefix = "node1",
          declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
          nginx_worker_processes = 1,
        })


        assert(helpers.start_kong{
          plugins = "service-protection,key-auth,exit-transformer",
          database = strategy ~= "off" and strategy or nil,
          declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
          db_update_frequency = 0.1,
          prefix = "node2",
          proxy_listen = "0.0.0.0:9100",
          admin_listen = "127.0.0.1:9101",
          admin_gui_listen = "127.0.0.1:9109",
          nginx_worker_processes = 1,
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong("node1")
        helpers.stop_kong("node2")

        if policy == "redis" then
          redis_helper.remove_user(redis_client, REDIS_USERNAME_VALID)
        end
      end)

      before_each(function()
        update_time()
      end)

      after_each(function()
        if proxy_client then proxy_client:close() end
      end)

      describe("Without authentication (IP address)", function()
        it("blocks if exceeding limit", function()
          for i = 1, 6 do
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test1.test"
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
            assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
            assert.is_nil(res.headers["retry-after"])
          end

          -- Additonal request, while limit is 6/window
          proxy_client = helpers.proxy_client()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test1.test"
            }
          })
          local body = assert.res_status(429, res)
          proxy_client:close()

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          local retry_after = tonumber(res.headers["retry-after"])
          assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
          assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))

          -- wait a bit longer than our retry window size (handles window floor)
          ngx_sleep(retry_after + 1)

          -- Additional request, sliding window is 0 < rate <= limit
          proxy_client = helpers.proxy_client()
          res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test1.test"
            }
          })
          assert.res_status(200, res)
          proxy_client:close()

          local rate = tonumber(res.headers["x-ratelimit-remaining-3"])
          assert.is_true(0 < rate and rate <= 6)
          rate = tonumber(res.headers["ratelimit-remaining"])
          assert.is_true(0 < rate and rate <= 6)
          assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
        end)

        it("falling back to local strategy if sync_rate = 0 when redis goes down", function()
          for i = 1, 3 do
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "route-26.test"
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            assert.are.same(3, tonumber(res.headers["x-ratelimit-limit-5"]))
            assert.are.same(3, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(3 - i, tonumber(res.headers["x-ratelimit-remaining-5"]))
            assert.are.same(3 - i, tonumber(res.headers["ratelimit-remaining"]))
            assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
            assert.is_nil(res.headers["retry-after"])
          end

          -- Additonal request, while limit is 3/window
          proxy_client = helpers.proxy_client()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "route-26.test"
            }
          })
          local body = assert.res_status(429, res)
          proxy_client:close()

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          local retry_after = tonumber(res.headers["retry-after"])
          assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
          assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))
        end)

        -- traditional mode but use redis strategy
        if policy ~= "redis" then
          it("sync counters in all nodes after PATCH", function()
            local window_size = plugin4.config.window_size[1]
            local limit = plugin4.config.limit[1]

            wait_for_next_fixed_window(window_size)

            for i = 1, limit do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get",
                headers = {
                  ["Host"] = "test15.test",
                }
              })
              assert.res_status(200, res)
              proxy_client:close()

              assert.are.same(limit, tonumber(res.headers["x-ratelimit-limit-" ..  window_size]))
              assert.are.same(limit, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(limit - i, tonumber(res.headers["x-ratelimit-remaining-" ..  window_size]))
              assert.are.same(limit - i, tonumber(res.headers["ratelimit-remaining"]))
              assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
              assert.is_nil(res.headers["retry-after"])
            end

            -- Additonal request on node1, while limit is 1/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test15.test",
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
            local retry_after = tonumber(res.headers["retry-after"])
            assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))

            -- Wait for counters to sync node2: 0.1+0.1
            ngx_sleep(plugin4.config.sync_rate + 0.1)

            -- Hit node2, while limit is 1/window
            proxy_client = helpers.proxy_client(nil, 9100)
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test15.test",
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
            local retry_after = tonumber(res.headers["retry-after"])
            assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))
            --]=]

            -- PATCH the plugin's window_size
            local res = assert(helpers.admin_client():send {
              method = "PATCH",
              path = "/plugins/" .. plugin4.id,
              body = {
                config = {
                  window_size = { 4 },
                }
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = cjson.decode(assert.res_status(200, res))
            assert.same(4, body.config.window_size[1])

            -- wait for the window: 4+1
            ngx_sleep(plugin4.config.window_size[1] + 1)
            window_size = 4

            -- Hit node2
            for i = 1, limit do
              proxy_client = helpers.proxy_client(nil, 9100)
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get",
                headers = {
                  ["Host"] = "test15.test",
                }
              })
              assert.res_status(200, res)
              proxy_client:close()

              assert.are.same(limit, tonumber(res.headers["x-ratelimit-limit-" .. window_size]))
              assert.are.same(limit, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(limit - i, tonumber(res.headers["x-ratelimit-remaining-" .. window_size]))
              assert.are.same(limit - i, tonumber(res.headers["ratelimit-remaining"]))
              assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
              assert.is_nil(res.headers["retry-after"])
            end

            -- Additonal request on node2, while limit is 1/window
            proxy_client = helpers.proxy_client(nil, 9100)
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test15.test",
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
            local retry_after = tonumber(res.headers["retry-after"])
            assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))

            --[= succeed locally
            -- Hit node1 so the sync timer starts
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test15.test",
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            -- Wait for counters to sync on node1: 0.1+0.1
            ngx_sleep(plugin4.config.sync_rate + 0.1)

            -- Additional request on node1, while limit is 1/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test15.test",
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
            local retry_after = tonumber(res.headers["retry-after"])
            assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))
            --]=]
          end)

          it("old namespace is cleared after namespace update", function()
            helpers.clean_logfile("node1/logs/error.log")
            helpers.clean_logfile("node2/logs/error.log")

            -- requests on node1 and node2 to create the namespace
            -- as we create the plugin by using `helpers.get_db_utils`
            -- which will not trigger worker_events to create the namespace
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test17.test",
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            proxy_client = helpers.proxy_client(nil, 9100)
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test17.test",
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            -- PATCH the plugin/namespace
            local res = assert(helpers.admin_client():send {
              method = "PATCH",
              path = "/plugins/" .. plugin1.id,
              body = {
                config = {
                  namespace = "new-ns"
                }
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            assert.res_status(200, res)

            assert.logfile("node1/logs/error.log").has.no.line("[error]", true)
            assert.logfile("node2/logs/error.log").has.no.line("[error]", true)

            helpers.pwait_until(function()
              assert.logfile("node1/logs/error.log").has.line("clearing old namespace Bk1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 30)
            end, 60)
            helpers.pwait_until(function()
              assert.logfile("node1/logs/error.log").has.line("attempting to add namespace new-ns", true, 30)
            end, 60)
            helpers.pwait_until(function()
              assert.logfile("node2/logs/error.log").has.line("clearing old namespace Bk1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 30)
            end, 60)
            helpers.pwait_until(function()
              assert.logfile("node2/logs/error.log").has.line("attempting to add namespace new-ns", true, 30)
            end, 60)
          end)

          it("we are NOT leaking any timers after DELETE", function()
            helpers.clean_logfile("node1/logs/error.log")
            helpers.clean_logfile("node2/logs/error.log")

            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test177.test",
              }
            })
            assert.res_status(200, res)

            local res = assert(helpers.proxy_client(nil, 9100):send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test177.test",
              }
            })
            assert.res_status(200, res)

            --[= succeed locally
            helpers.wait_for_file_contents("node1/logs/error.log", 20)
            helpers.pwait_until(function()
              assert.logfile("node1/logs/error.log").has.line("start sync 046F4FC717A147C2A446A4BEA763CF1E", true, 20)
            end, 60)
            helpers.wait_for_file_contents("node2/logs/error.log", 20)
            helpers.pwait_until(function()
              assert.logfile("node2/logs/error.log").has.line("start sync 046F4FC717A147C2A446A4BEA763CF1E", true, 20)
            end, 60)
            --]=]

            -- DELETE the plugin
            local res = assert(helpers.admin_client():send {
              method = "DELETE",
              path = "/plugins/" .. plugin2.id,
            })
            assert.res_status(204, res)

            assert.logfile("node1/logs/error.log").has.no.line("[error]", true)
            assert.logfile("node2/logs/error.log").has.no.line("[error]", true)
            --[= succeed locally
            helpers.pwait_until(function()
              assert.logfile("node1/logs/error.log").has.line("stale timer of namespace 046F4FC717A147C2A446A4BEA763CF1E", true, 20)
            end, 60)
            helpers.pwait_until(function()
              assert.logfile("node2/logs/error.log").has.line("stale timer of namespace 046F4FC717A147C2A446A4BEA763CF1E", true, 20)
            end, 60)
            --]=]
          end)

          it("new plugin works in a new service in traditional mode", function()
            helpers.clean_logfile("node1/logs/error.log")
            helpers.clean_logfile("node2/logs/error.log")

            -- POST a service
            local res = assert(helpers.admin_client():send {
              method = "POST",
              path = "/services/",
              body = {
                protocol = "http",
                host = "127.0.0.1",
                port = 15555,
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)

            -- POST a route
            local res = assert(helpers.admin_client():send {
              method = "POST",
              path = "/services/" .. json.id .. "/routes/",
              body = {
                name = "testt20",
                hosts = { "testt20.test" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            assert.res_status(201, res)

            -- POST the plugin
            local res = assert(helpers.admin_client():send {
              method = "POST",
              path = "/services/" .. json.id .. "/plugins/",
              body = {
                name = "service-protection",
                config = {
                  strategy = policy,
                  window_size = { 5 },
                  namespace = "Ek1krkTWBqmcKEQVW5cQNLgikuKygjnu",
                  limit = { 6 },
                  sync_rate = (policy ~= "local" and 1 or nil),
                  redis = redis_configuration,
                }
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })
            assert.res_status(201, res)

            -- Wait to check for the CREATED plugin with the datastore
            ngx_sleep(2)

            assert.logfile("node1/logs/error.log").has.no.line("[error]", true)
            assert.logfile("node2/logs/error.log").has.no.line("[error]", true)
            helpers.pwait_until(function()
              assert.logfile("node1/logs/error.log").has.line("attempting to add namespace Ek1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 30)
            end, 60)
            helpers.pwait_until(function()
              assert.logfile("node2/logs/error.log").has.line("attempting to add namespace Ek1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 30)
            end, 60)

            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "testt20.test",
              }
            })
            assert.res_status(200, res)

            local res = assert(helpers.proxy_client(nil, 9100):send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "testt20.test",
              }
            })
            assert.res_status(200, res)
          end)
        end

        it("local strategy works in traditional and dbless mode", function()
          for i = 1, 6 do
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test20.test",
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-10"]))
            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-10"]))
            assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
            assert.is_nil(res.headers["retry-after"])
          end

          -- Additonal request, while limit is 6/window
          proxy_client = helpers.proxy_client()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test20.test",
            }
          })
          local body = assert.res_status(429, res)
          proxy_client:close()

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          local retry_after = tonumber(res.headers["retry-after"])
          assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
          assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))
        end)

        it("resets the counter", function()
          -- clear our windows entirely: 3*2
          ngx_sleep(MOCK_RATE * 2)

          -- Additonal request, sliding window is reset and one less than limit
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test1.test"
            }
          })
          assert.res_status(200, res)
          assert.same(5, tonumber(res.headers["x-ratelimit-remaining-3"]))
          assert.same(5, tonumber(res.headers["ratelimit-remaining"]))
          assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
          assert.is_nil(res.headers["retry-after"])
        end)

        local name = "handles multiple limits"
        if policy == "redis" then
          name = "#flaky-candidate " .. name
        end
        it(name, function()
          local limits = {
            ["5"] = 3,
            ["10"] = 5,
          }

          for i = 1, 3 do
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test2.test"
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            assert.same(limits["5"], tonumber(res.headers["x-ratelimit-limit-5"]))
            assert.same(limits["5"], tonumber(res.headers["ratelimit-limit"]))
            assert.same(limits["5"] - i, tonumber(res.headers["x-ratelimit-remaining-5"]))
            assert.same(limits["5"] - i, tonumber(res.headers["ratelimit-remaining"]))
            assert.same(limits["10"], tonumber(res.headers["x-ratelimit-limit-10"]))
            assert.same(limits["10"] - i, tonumber(res.headers["x-ratelimit-remaining-10"]))
          end

          -- once we have reached a limit, ensure we do not dip below 0,
          -- and do not alter other limits
          for i = 1, 5 do
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test2.test"
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
            assert.same(2, tonumber(res.headers["x-ratelimit-remaining-10"]))
            assert.same(0, tonumber(res.headers["x-ratelimit-remaining-5"]))
            assert.same(0, tonumber(res.headers["ratelimit-remaining"])) -- Should only correspond to the current rate-limit being applied
          end
        end)

        it("implements a fixed window if instructed to do so", function()
          local window_size = plugin3.config.window_size[1]
          local limit = plugin3.config.limit[1]
          local window_start = wait_for_next_fixed_window(window_size)

          for i = 1, limit do
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test6.test"
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            assert.are.same(limit, tonumber(res.headers["x-ratelimit-limit-" ..  window_size]))
            assert.are.same(limit, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(limit - i, tonumber(res.headers["x-ratelimit-remaining-" .. window_size]))
            assert.are.same(limit - i, tonumber(res.headers["ratelimit-remaining"]))
          end

          -- Additonal request, while limit is 1/window
          proxy_client = helpers.proxy_client()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test6.test"
            }
          })
          local elapsed_time = (time() - window_start)
          local body = assert.res_status(429, res)
          proxy_client:close()

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          local retry_after = tonumber(res.headers["retry-after"])
          local ratelimit_reset = tonumber(res.headers["ratelimit-reset"])

          -- Calculate the expected wait for a fixed window
          local expected_retry_after = window_size - elapsed_time
          expected_retry_after = (expected_retry_after == 0) and window_size or expected_retry_after
          assert.same(expected_retry_after, retry_after)
          assert.same(retry_after, ratelimit_reset)

          -- wait a bit longer than our retry window size
          ngx_sleep(retry_after + 0.5)

          -- Additonal request, window/rate is reset
          proxy_client = helpers.proxy_client()
          res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test6.test"
            }
          })
          assert.res_status(200, res)
          proxy_client:close()

          assert.same(limit - 1, tonumber(res.headers["x-ratelimit-remaining-" .. window_size]))
          assert.same(limit - 1, tonumber(res.headers["ratelimit-remaining"]))
        end)

        it("hides headers if hide_client_headers is true", function()
          wait_for_next_fixed_window(MOCK_RATE)
          local res
          for i = 1, 6 do
            proxy_client = helpers.proxy_client()
            res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test9.test"
              }
            })

            assert.is_nil(res.headers["x-ratelimit-remaining-3"])
            assert.is_nil(res.headers["ratelimit-remaining"])
            assert.is_nil(res.headers["x-ratelimit-limit-3"])
            assert.is_nil(res.headers["ratelimit-limit"])
            assert.is_nil(res.headers["ratelimit-reset"])
          end

          -- Ensure the Retry-After header is not available for 429 errors
          assert.res_status(429, res)
          assert.is_nil(res.headers["retry-after"])
        end)

        describe("With retry_after_jitter_max > 0", function()
          it("on hitting a limit adds a jitter to the Retry-After header", function()
            local request = build_request("test13.test", "/get")

            -- issue 2 requests to use all the quota 2/window for test13.test
            for _ = 1, 2 do
              local res = assert(helpers.proxy_client():send(request))
              assert.res_status(200, res)
            end

            -- issue 3rd request to hit the limit
            local res = assert(helpers.proxy_client():send(request))
            assert.res_status(429, res)

            local retry_after = tonumber(res.headers["retry-after"])
            local ratelimit_reset = tonumber(res.headers["ratelimit-reset"])

            -- check that jitter was added to retry_after
            assert.is_true(retry_after > ratelimit_reset)
            assert.is_true(retry_after <= ratelimit_reset + 5) -- retry_after_jitter_max = 5
          end)

          it("on hitting a limit does not set Retry-After header (hide_client_headers = true)", function()
            local request = build_request("test14.test", "/get")

            -- issue 2 requests to use all the quota 2/window for test14.test
            for _ = 1, 2 do
              local res = assert(helpers.proxy_client():send(request))
              assert.res_status(200, res)
            end

            -- issue 3rd request to hit the limit
            local res = assert(helpers.proxy_client():send(request))
            assert.res_status(429, res)

            -- check that retry_after is not set
            assert.is_nil(res.headers["retry-after"])
          end)
        end)

        it("don't count the rejected requests if disable_penalty is true", function()
          local res = {}
          -- the first 10 requests are used to make sure the rate has exceeded the limit(5)
          for i = 1, 10 do
            proxy_client = helpers.proxy_client()
            res[i] = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test21.test"
              }
            })
            proxy_client:close()
          end
          -- the later 20 requests last for more than 20 * 0.5 = 10s,
          -- which is twice the window_size(5)
          -- the rate is 10 request per window_size, while the limit is 5
          for i = 11, 30 do
            proxy_client = helpers.proxy_client()
            res[i] = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test21.test"
              }
            })
            proxy_client:close()
            ngx_sleep(0.5)
          end

          local num200 = 0
          local num429 = 0
          for i = 1, 10 do
            if res[i].status == 200 then
              num200 = num200 + 1
            elseif res[i].status == 429 then
              num429 = num429 + 1
            end
          end
          -- no other responses except 200 and 429
          assert.same(10, num200 + num429)

          num200 = 0
          num429 = 0
          for i = 11, 30 do
            if res[i].status == 200 then
              num200 = num200 + 1
            elseif res[i].status == 429 then
              num429 = num429 + 1
            end
          end

          -- no other responses except 200 and 429
          assert.same(20, num200 + num429)

          -- the remaining requests should not be rejected forever
          -- the later 20 requests last for more than 10s (twice the window_size)
          assert.are_not.same(0, num200)
        end)

        it("count the rejected requests if disable_penalty is false", function()
          local res = {}
          -- the first 10 requests are used to make sure the rate has exceeded the limit(5)
          for i = 1, 10 do
            proxy_client = helpers.proxy_client()
            res[i] = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test22.test"
              }
            })
            proxy_client:close()
          end
          -- the later 20 requests last for more than 20 * 0.5 = 10s,
          -- which is twice the window_size(5)
          -- the rate is 10 request per window_size, while the limit is 5
          for i = 11, 30 do
            res[i] = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test22.test"
              }
            })
            ngx_sleep(0.5)
          end

          local num200 = 0
          local num429 = 0
          for i = 1, 10 do
            if res[i].status == 200 then
              num200 = num200 + 1
            elseif res[i].status == 429 then
              num429 = num429 + 1
            end
          end
          -- no other responses except 200 and 429
          assert.same(10, num200 + num429)

          -- the remaining requests should be rejected forever
          for i = 11, 30 do
            assert.res_status(429, res[i])
          end
        end)
      end)
      describe("With authentication", function()
        describe("Route-specific plugin", function()
          it("blocks if exceeding limit", function()
            for i = 1, 6 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get?apikey=apikey123",
                headers = {
                  ["Host"] = "test3.test"
                }
              })
              assert.res_status(200, res)
              proxy_client:close()

              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
              assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            end

            -- Third query, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test3.test"
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
            assert.is_true(tonumber(res.headers["retry-after"]) >= 0) -- Uses sliding window and is executed in quick succession

          end)

          it("emits response headers upon exceeding limit", function()
            local res
            helpers.wait_until(function()
              proxy_client = helpers.proxy_client()
              res = assert(proxy_client:send {
                method = "GET",
                path = "/get?apikey=apikey123",
                headers = {
                  ["Host"] = "test23.test"
                }
              })

              if res and res.status == 429 then
                return true

              else
                proxy_client:close()
              end
            end, 5, 0.5)

            local body = assert.res_status(429, res)
            assert.same({ message = "API rate limit exceeded" }, cjson.decode(body))

            assert.is_truthy(res.headers["retry-after"])
            assert.is_truthy(res.headers["ratelimit-reset"])
            assert.equal("3", res.headers["ratelimit-limit"])
            assert.equal("0", res.headers["ratelimit-remaining"])
            assert.equal("3", res.headers["x-rateLimit-limit-3"])
            assert.equal("0", res.headers["x-rateLimit-remaining-3"])

            if proxy_client then proxy_client:close() end
          end)
        end)
      end)

      it("work with custom responses", function()
        local res
        for i = 1, 7 do
          proxy_client = helpers.proxy_client()
          res = assert(proxy_client:send {
            method = "GET",
            headers = {
              ["Host"] = "route_for_custom_response.test"
            }
          })
          if i ~= 7 then
            assert.res_status(200, res)
            proxy_client:close()
          end
        end

        assert.are.same(0, tonumber(res.headers["x-ratelimit-remaining-5"]))
        local body = assert.res_status(405, res)
        local json = cjson.decode(body)
        assert.same({ message = "Testing" }, json)
        proxy_client:close()
      end)
    end)

    if strategy ~= "off" then
      describe("service-protection Hybrid Mode with strategy #" .. strategy .. "#", function()
        local plugin5, plugin6
        local proxy_client
        local redis_client

        lazy_setup(function()
          if policy == "redis" then
            redis_client = redis_helper.connect(REDIS_HOST, REDIS_PORT)
            redis_client:flush_all()
            redis_helper.add_admin_user(redis_client, REDIS_USERNAME_VALID, REDIS_PASSWORD_VALID)
          end

          local bp = helpers.get_db_utils(strategy ~= "off" and strategy or nil,
                                          nil, {"service-protection"})

          local service16 = assert(bp.services:insert {
            name = "svc16",
            url = "http://127.0.0.1:" .. HTTP_SERVER_PORT_16,
          })
          assert(bp.routes:insert {
            name = "test-16",
            hosts = { "test16.test" },
            service = { id = service16.id },
          })
          plugin5 = assert(bp.plugins:insert(
            build_plugin_fn("redis")(
              service16.id, 5, 1, 0.1, nil,
              nil, redis_configuration,
              {namespace = "ED83AE45-887D-4A73-8AC8-5120C0D7E6E9" }
            )
          ))

          local service18 = assert(bp.services:insert {
            host = "test18.test",
          })
          assert(bp.routes:insert {
            name = "test-18",
            service = { id = service16.id },
            hosts = { "test18.test" },
          })
          assert(bp.plugins:insert(
            build_plugin_fn("redis")(
              service18.id, 5, 6, 1, nil,
              nil, redis_configuration,
              { namespace = "Ck1krkTWBqmcKEQVW5cQNLgikuKygjnu" }
            )
          ))

          local service20 = assert(bp.services:insert())
          assert(bp.routes:insert {
            name = "test-20",
            hosts = { "test20.test" },
            service = { id = service20.id }
          })
          assert(bp.plugins:insert(
            build_plugin_fn("local")(
              service20.id, 5, 2, -1, nil,
              nil, nil, { namespace = "7674e5db-0dfe-4c95-af4a-b71f61d4f9dd" }
            )
          ))

          local service21 = assert(bp.services:insert {
            host = "test21.test",
          })
          assert(bp.routes:insert {
            name = "test-21",
            hosts = { "test21.test" },
            service = { id = service21.id }
          })
          plugin6 = assert(bp.plugins:insert(
            build_plugin_fn("local")(
              service21.id, 5, 2, -1, nil,
              nil, nil, { namespace = "9a34c29b-1d3b-38e5-2ef0-a82a19d71682" }
            )
          ))

          assert(helpers.start_kong({
            plugins = "service-protection,key-auth",
            role = "control_plane",
            cluster_cert = "spec/fixtures/kong_clustering.crt",
            cluster_cert_key = "spec/fixtures/kong_clustering.key",
            lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
            database = strategy,
            db_update_frequency = 0.1,
            admin_listen = "127.0.0.1:9103",
            cluster_listen = "127.0.0.1:9005",
            admin_gui_listen = "127.0.0.1:9209",
            prefix = "cp",
            nginx_worker_processes = 1,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))

          assert(helpers.start_kong({
            plugins = "service-protection,key-auth",
            role = "data_plane",
            database = "off",
            cluster_cert = "spec/fixtures/kong_clustering.crt",
            cluster_cert_key = "spec/fixtures/kong_clustering.key",
            lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
            cluster_control_plane = "127.0.0.1:9005",
            proxy_listen = "0.0.0.0:" .. PROXY_PORT,
            prefix = "dp1",
            nginx_worker_processes = 1,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))

          assert(helpers.start_kong({
            plugins = "service-protection,key-auth",
            role = "data_plane",
            database = "off",
            cluster_cert = "spec/fixtures/kong_clustering.crt",
            cluster_cert_key = "spec/fixtures/kong_clustering.key",
            lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
            cluster_control_plane = "127.0.0.1:9005",
            proxy_listen = "0.0.0.0:9104",
            prefix = "dp2",
            nginx_worker_processes = 1,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))

          helpers.wait_for_file_contents("cp/pids/nginx.pid")
          helpers.wait_for_file_contents("dp1/pids/nginx.pid")
          helpers.wait_for_file_contents("dp2/pids/nginx.pid")
        end)

        lazy_teardown(function()
          helpers.stop_kong("cp")
          helpers.stop_kong("dp1")
          helpers.stop_kong("dp2")
          helpers.kill_all()
        end)

        it("new plugin is created in a new route", function()
          helpers.clean_logfile("dp1/logs/error.log")
          helpers.clean_logfile("dp2/logs/error.log")
          helpers.clean_logfile("cp/logs/error.log")

          -- POST a service in the CP
          local res = assert(helpers.admin_client(nil, 9103):post("/services", {
            body = { name = "mockbin-service", url = "http://127.0.0.1:" .. HTTP_SERVER_PORT, },
            headers = {["Content-Type"] = "application/json"}
          }))
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          -- POST a route in the CP
          local res = assert(helpers.admin_client(nil, 9103):send {
            method = "POST",
            path = "/services/" .. json.id .. "/routes/",
            body = {
              name = "testt19",
              hosts = { "testt19.test" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)

          -- POST the plugin in the CP
          local res = assert(helpers.admin_client(nil, 9103):send {
            method = "POST",
            path = "/services/" .. json.id .. "/plugins/",
            body = {
              name = "service-protection",
              config = {
                strategy = "redis",
                window_size = { 5 },
                namespace = "Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu",
                limit = { 6 },
                sync_rate = 1,
                redis = redis_configuration,
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)

          -- wait for created entities sync with DP
          ngx_sleep(1)

          local mock = http_mock.new(HTTP_SERVER_PORT)
          mock:start()
          finally(function()
            mock:stop()
          end)
          ngx_sleep(1)
          proxy_client = helpers.proxy_client(nil, PROXY_PORT)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "testt19.test",
            }
          })
          assert.res_status(200, res)
          mock.eventually:has_one_without_error()

          ngx_sleep(1)
          proxy_client = helpers.proxy_client(nil, 9104)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "testt19.test",
            }
          })
          assert.res_status(200, res)
          proxy_client:close()
          mock.eventually:has_one_without_error()

          helpers.wait_for_file_contents("dp1/logs/error.log")
          helpers.pwait_until(function()
            assert.logfile("dp1/logs/error.log").has.line("start sync Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 20)
          end, 60)
          helpers.wait_for_file_contents("dp2/logs/error.log")
          helpers.pwait_until(function()
            assert.logfile("dp2/logs/error.log").has.line("start sync Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 20)
          end, 60)
          -- won't create namespace or start sync on CP after plugin create
          helpers.wait_for_file_contents("cp/logs/error.log")
          assert.logfile("cp/logs/error.log").has.no.line("attempting to add namespace Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 20)
          assert.logfile("cp/logs/error.log").has.no.line("start sync Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 20)
        end)

        it("won't reset namespace or start sync on cp after plugin update", function()
          helpers.clean_logfile("cp/logs/error.log")

          -- PATCH the plugin
          local res = assert(helpers.admin_client(nil, 9103):send {
            method = "PATCH",
            path = "/plugins/" .. plugin6.id,
            body = {
              config = {
                limit = { 3 }
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(200, res)

          helpers.wait_for_file_contents("cp/logs/error.log")
          assert.logfile("cp/logs/error.log").has.no.line("clear and reset 9a34c29b-1d3b-38e5-2ef0-a82a19d71682", true, 20)
          assert.logfile("cp/logs/error.log").has.no.line("start sync 9a34c29b-1d3b-38e5-2ef0-a82a19d71682", true, 20)
        end)

        it("sync counters in all DP nodes after PATCH", function()
          local mock = http_mock.new(HTTP_SERVER_PORT_16)
          mock:start()
          finally(function()
            mock:stop()
          end)

          local window_size = plugin5.config.window_size[1]
          local limit = plugin5.config.limit[1]

          -- Hit DP 1
          for i = 1, limit do
            ngx_sleep(1)
            proxy_client = helpers.proxy_client(nil, PROXY_PORT)
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/",
              headers = {
                ["Host"] = "test16.test",
              }
            })
            assert.res_status(200, res)
            proxy_client:close()
            mock.eventually:has_one_without_error()

            assert.are.same(limit, tonumber(res.headers["x-ratelimit-limit-".. window_size]))
            assert.are.same(limit, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(limit - i, tonumber(res.headers["x-ratelimit-remaining-" .. window_size]))
            assert.are.same(limit - i, tonumber(res.headers["ratelimit-remaining"]))
            assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
            assert.is_nil(res.headers["retry-after"])
          end

          -- Additonal request ON DP 1, while limit is 1/window
          proxy_client = helpers.proxy_client(nil, PROXY_PORT)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "test16.test",
            }
          })
          local body = assert.res_status(429, res)
          proxy_client:close()

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          local retry_after = tonumber(res.headers["retry-after"])
          assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
          assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))

          --[= succeed locally
           -- Wait for counters to sync ON DP 2: 0.1+0.1
           ngx_sleep(plugin5.config.sync_rate + 0.1)

          -- Hit DP 2
          proxy_client = helpers.proxy_client(nil, 9104)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "test16.test",
            }
          })
          local body = assert.res_status(429, res)
          proxy_client:close()

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          local retry_after = tonumber(res.headers["retry-after"])
          assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
          assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))
          --]=]

          -- PATCH the plugin's window_size on CP
          local res = assert(helpers.admin_client(nil, 9103):send {
            method = "PATCH",
            path = "/plugins/" .. plugin5.id,
            body = {
              config = {
                window_size = { 4 },
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.same(4, body.config.window_size[1])

          -- wait for the window: 4+1
          ngx_sleep(plugin5.config.window_size[1] + 1)
          window_size = 4

          -- Hit DP 2
          for i = 1, limit do
            ngx_sleep(1)
            proxy_client = helpers.proxy_client(nil, 9104)
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/",
              headers = {
                ["Host"] = "test16.test",
              }
            })
            assert.res_status(200, res)
            proxy_client:close()
            mock.eventually:has_one_without_error()

            assert.are.same(limit, tonumber(res.headers["x-ratelimit-limit-" .. window_size]))
            assert.are.same(limit, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(limit - i, tonumber(res.headers["x-ratelimit-remaining-" .. window_size]))
            assert.are.same(limit - i, tonumber(res.headers["ratelimit-remaining"]))
            assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
            assert.is_nil(res.headers["retry-after"])
          end

          -- Additonal request ON DP 2, while limit is 1/window
          proxy_client = helpers.proxy_client(nil, 9104)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "test16.test",
            }
          })
          local body = assert.res_status(429, res)
          proxy_client:close()

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          local retry_after = tonumber(res.headers["retry-after"])
          assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
          assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))

          --[= succeed locally
          -- Wait for counters to sync ON DP 1: 0.1+0.1
          ngx_sleep(plugin5.config.sync_rate + 0.1)

          -- Hit DP 1, while limit is 1/window
          proxy_client = helpers.proxy_client(nil, PROXY_PORT)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "test16.test",
            }
          })
          local body = assert.res_status(429, res)
          proxy_client:close()

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          local retry_after = tonumber(res.headers["retry-after"])
          assert.is_true(retry_after >= 0) -- Uses sliding window and is executed in quick succession
          assert.same(retry_after, tonumber(res.headers["ratelimit-reset"]))
          --]=]
        end)
      end)
    end
  end
end

for _, strategy in ipairs({ "off" }) do
  local PLUGIN_NAME = "service-protection"
  describe(PLUGIN_NAME .. " with strategy #" .. strategy, function()
    local yaml_templ, yaml_file
    local admin_client, proxy_client
    local err_log_file

    lazy_setup(function()
      yaml_templ = [=[
        _format_version: '3.0'
        services:
        - name: mock_upstream
          url: %s
          routes:
          - name: mock_route
            hosts:
            - sp.test
            paths:
            - /anything
            plugins:
            - name: %s
              config:
                namespace: sp
                window_size:
                - %s
                limit:
                - 5
                strategy: local
                sync_rate: null
      ]=]
      yaml_file = helpers.make_yaml_file(yaml_templ:format("http://127.0.0.1:15555", PLUGIN_NAME, 30))

      assert(helpers.start_kong({
        database = strategy,
        plugins = "bundled," .. PLUGIN_NAME,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and yaml_file or nil,
      }))

      err_log_file = helpers.test_conf.nginx_err_logs
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      helpers.clean_logfile(err_log_file)
    end)

    after_each(function()
      if admin_client then admin_client:close() end
      if proxy_client then proxy_client:close() end

      helpers.clean_logfile(err_log_file)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      os.remove(yaml_file)
    end)

    it("works when value of sync_rate is nil", function()
      local dc = assert(admin_client:send {
        method = "GET",
        path = "/config",
        headers = {
          ["Content-Type"] = "application/json"
        },
      })
      assert.res_status(200, dc)

      dc = assert(admin_client:send {
        method = "POST",
        path = "/config?check_hash=1",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          config = yaml_templ:format("http://127.0.0.1:15555", PLUGIN_NAME, 60)
        }
      })
      assert.res_status(201, dc)

      local err_msg = "failed to execute plugin '" .. PLUGIN_NAME .. ":configure \\(.*handler\\.lua:\\d{1,}: attempt to compare number with nil\\)"
      assert.logfile(err_log_file).has.no.line(err_msg, false)

    end)

  end)

end
