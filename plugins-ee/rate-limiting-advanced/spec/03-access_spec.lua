-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local cjson = require "cjson"
local redis = require "kong.enterprise_edition.redis"
local version = require "version"


local HTTP_SERVER_PORT_16 = helpers.get_available_port()
local HTTP_SERVER_PORT_20 = helpers.get_available_port()
local HTTP_SERVER_PORT = helpers.get_available_port()
local PROXY_PORT = helpers.get_available_port()
local REDIS_HOST = helpers.redis_host
local REDIS_PORT = helpers.redis_port or 6379
local REDIS_DATABASE = 1

local REDIS_USERNAME_VALID = "rla-user"
local REDIS_PASSWORD_VALID = "rla-pass"

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
  return function (route_id, windows, limits, sync_rate, retry_jitter, hide_headers, redis_configuration, extra_conf)
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
      name = "rate-limiting-advanced",
      route = { id = route_id },
      config = conf
    }
  end
end

local function redis_connect()
  local red = assert(redis.connection({
    host = REDIS_HOST,
    port = REDIS_PORT,
  }))
  local red_version = string.match(red:info(), 'redis_version:([%g]+)\r\n')
  return red, assert(version(red_version))
end

local function redis_version(policy)
  local red, red_version = redis_connect()
  red:close()
  return red_version
end

local function add_redis_user(policy)
  if policy == "redis" then
    local red, red_version = redis_connect()
    if red_version >= version("6.0.0") then
      assert(red:acl("setuser", REDIS_USERNAME_VALID, "on", "allkeys", "+@all", ">" .. REDIS_PASSWORD_VALID))
    end
    red:close()
  end
end

local function remove_redis_user(policy)
  if policy == "redis" then
    local red, red_version = redis_connect()
    if red_version >= version("6.0.0") then
      if REDIS_USERNAME_VALID == "default" then
        assert(red:acl("setuser", REDIS_USERNAME_VALID, "nopass"))

      else

        assert(red:acl("deluser", REDIS_USERNAME_VALID))
      end
    end
    red:close()
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

  if policy == "redis" and redis_version() >= version("6.0.0") then
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
  local MOCK_GROUP_LIMIT = 10
  local MOCK_GROUP_SIZE = 10
  local MOCK_ORIGINAL_LIMIT = 6

  local base = "rate-limiting-advanced [#"..strategy.."]"

  -- helper function to build plugin config
  local build_plugin = build_plugin_fn(policy)

  for redis_description, redis_configuration in pairs(redis_test_configurations(policy)) do
    local s = base
    if policy == "redis" then
      s = s .. " [#" .. redis_description .. "]"
    end
    describe(s, function()
      local bp, db, consumer1, consumer2, plugin3, plugin5, plugin6, plugin10, plugin15, consumer_in_group
      local consumer_in_group_no_config
      local proxy_client

      lazy_setup(function()
        redis.flush_redis(REDIS_HOST, REDIS_PORT, REDIS_DATABASE, nil, nil)
        add_redis_user(policy)

        bp, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil,
                                  nil,
                                  {"rate-limiting-advanced", "exit-transformer"})

        consumer1 = assert(bp.consumers:insert {
          custom_id = "provider_123"
        })
        assert(bp.keyauth_credentials:insert {
          key = "apikey122",
          consumer = { id = consumer1.id },
        })

        consumer2 = assert(bp.consumers:insert {
          custom_id = "provider_124"
        })

        consumer_in_group = assert(bp.consumers:insert {
          custom_id = "consumer_in_group"
        })

        consumer_in_group_no_config = assert(bp.consumers:insert {
          custom_id = "consumer_in_group_no_config"
        })

        if strategy ~= "off" then
          local consumer_group = assert(db.consumer_groups:insert({
            name = "test_consumer_group"
          }))

          local consumer_group_no_config = assert(db.consumer_groups:insert({
            name = "test_consumer_group_no_config"
          }))

          assert(db.consumer_group_consumers:insert({
            consumer          = { id = consumer_in_group.id },
            consumer_group 	  = { id = consumer_group.id },
          }))

          assert(db.consumer_group_consumers:insert({
            consumer          = { id = consumer_in_group_no_config.id },
            consumer_group 	  = { id = consumer_group_no_config.id },
          }))

          assert(db.consumer_group_plugins:insert({
              name = "rate-limiting-advanced",
              consumer_group = { id = consumer_group.id },
              config = {
                window_size = { MOCK_GROUP_SIZE },
                limit = { MOCK_GROUP_LIMIT },
              }
          }))

          assert(bp.keyauth_credentials:insert {
            key = "apikeycg",
            consumer = { id = consumer_in_group.id },
          })

          assert(bp.keyauth_credentials:insert {
            key = "apikeycgnoconfig",
            consumer = { id = consumer_in_group_no_config.id },
          })
        end

        assert(bp.keyauth_credentials:insert {
          key = "apikey123",
          consumer = { id = consumer2.id },
        })
        assert(bp.keyauth_credentials:insert {
          key = "apikey333",
          consumer = { id = consumer2.id },
        })

        local route1 = assert(bp.routes:insert {
          name = "route-1",
          hosts = { "test1.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(route1.id, MOCK_RATE, 6, 10, nil, nil, redis_configuration)
        ))

        local route2 = assert(bp.routes:insert {
          name = "route-2",
          hosts = { "test2.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(route2.id, { 5, 10 }, { 3, 5 }, 10, nil, nil, redis_configuration)
        ))

        local route3 = assert(bp.routes:insert {
          name = "route-3",
          hosts = { "test3.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route3.id },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route3.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration, { identifier = "credential" }
          )
        ))

        local route4 = assert(bp.routes:insert {
          name = "route-4",
          hosts = { "test4.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route4.id, MOCK_RATE, 3, 10, nil,
            nil, redis_configuration, { namespace = "foo" }
          )
        ))

        local route5 = assert(bp.routes:insert {
          name = "route-5",
          hosts = { "test5.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route5.id, MOCK_RATE, 3, 10, nil,
            nil, redis_configuration, { namespace = "foo" }
          )
        ))

        local route6 = assert(bp.routes:insert {
          name = "route-6",
          hosts = { "test6.test" },
        })
        plugin6 = assert(bp.plugins:insert(
          build_plugin(
            route6.id, 5, 2, 2, nil,
            nil, redis_configuration,
            { window_type = "fixed", retry_after_jitter_max = nil }
          )
        ))

        local route7 = assert(bp.routes:insert {
          name = "route-7",
          hosts = { "test7.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route7.id },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route7.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration
          )
        ))

        local route8 = assert(bp.routes:insert {
          name = "route-8",
          hosts = { "test8.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route8.id },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route8.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration, { identifier = "ip" }
          )
        ))

        local route9 = assert(bp.routes:insert {
          name = "route-9",
          hosts = { "test9.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route9.id, MOCK_RATE, 1, 10, nil,
            true, redis_configuration, { window_type = "fixed" }
          )
        ))

        local route10 = assert(bp.routes:insert {
          name = "route-10",
          hosts = { "test10.test" },
        })

        plugin10 = assert(bp.plugins:insert(
          build_plugin(
            route10.id, 10, 6, 10, nil,
            nil, redis_configuration,
            { window_type = "fixed", identifier = "service" }
          )
        ))

        local route11 = assert(bp.routes:insert {
          name = "route-11",
          hosts = { "test11.test" },
        })

        assert(bp.plugins:insert(
          build_plugin(
            route11.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration,
            { window_type = "fixed", identifier = "service" }
          )
        ))

        local route12 = assert(bp.routes:insert {
          name = "route-12",
          hosts = { "test12.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route12.id },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route12.id, MOCK_RATE, 6, 10, nil,
            nil, redis_configuration,
            { header_name = "x-email-address", identifier = "header" }
          )
        ))

        local route13 = assert(bp.routes:insert {
          name = "test-13",
          hosts = { "test13.test" },
        })
        assert(bp.plugins:insert(build_plugin(route13.id, MOCK_RATE, 2, 0, 5, false, redis_configuration)))

        local route14 = assert(bp.routes:insert {
          name = "test-14",
          hosts = { "test14.test" },
        })
        assert(bp.plugins:insert(build_plugin(route14.id, MOCK_RATE, 2, 0, 5, true, redis_configuration)))

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
          name = "rate-limiting-advanced",
          service = { id = shared_service.id },
          config = {
            strategy = policy,
            identifier = "service",
            window_size = { 10 },
            window_type = "fixed",
            limit = { 6 },
            sync_rate = (policy ~= "local" and 0 or nil),
            redis = redis_configuration,
          },
        }))

        local route15 = assert(bp.routes:insert {
          name = "test-15",
          hosts = { "test15.test" },
        })
        plugin15 = assert(bp.plugins:insert(
          build_plugin_fn("redis")(
            route15.id, 5, 1, 0.1, nil,
            nil, redis_configuration,
            { namespace = "2D8851DEAC3D4FC5889CF03A9836948F", }
          )
        ))

        local route17 = assert(bp.routes:insert {
          name = "test-17",
          hosts = { "test17.test" },
        })
        plugin3 = assert(bp.plugins:insert(
          build_plugin_fn("cluster")(
            route17.id, 5, 6, 1, nil,
            nil, nil,
            { namespace = "Bk1krkTWBqmcKEQVW5cQNLgikuKygjnu" }
          )
        ))

        local route177 = assert(bp.routes:insert {
          name = "test-177",
          hosts = { "test177.test" },
        })
        plugin5 = assert(bp.plugins:insert(
          build_plugin_fn("cluster")(
            route177.id, 5, 6, 1, nil,
            nil, nil,
            { namespace = "046F4FC717A147C2A446A4BEA763CF1E" }
          )
        ))

        local route19 = assert(bp.routes:insert {
          name = "test-19",
          hosts = { "test19.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route19.id, 5, 6, 1, nil,
            nil, redis_configuration,
            { identifier = "path", path = "/status/200" }
          )
        ))

        local route20 = assert(bp.routes:insert {
          name = "test-20",
          hosts = { "test20.test" },
        })
        assert(bp.plugins:insert(
          build_plugin(
            route20.id, 10, 6, nil, nil,
            nil, redis_configuration
          )
        ))

        local route21 = assert(bp.routes:insert {
          name = "route-21",
          hosts = { "test21.test" },
        })

        assert(bp.plugins:insert {
          name = "rate-limiting-advanced",
          route = { id = route21.id },
          config = {
            strategy = policy,
            window_size = { 5 },
            limit = { 5 },
            sync_rate = (policy ~= "local" and 1 or nil),
            redis = redis_configuration,
            disable_penalty = true,
          }
        })

        local route22 = assert(bp.routes:insert {
          name = "route-22",
          hosts = { "test22.test" },
        })

        assert(bp.plugins:insert {
          name = "rate-limiting-advanced",
          route = { id = route22.id },
          config = {
            strategy = policy,
            window_size = { 5 },
            limit = { 5 },
            sync_rate = (policy ~= "local" and 1 or nil),
            redis = redis_configuration,
            -- disable_penalty = false,
          }
        })

        local route23 = assert(bp.routes:insert {
          name = "route-23",
          hosts = { "test23.test" },
        })
        assert(bp.plugins:insert {
          name = "key-auth",
          route = { id = route23.id },
        })
        local function_body_headers = [[
          return function(status, body, headers)
            if not body or not body.message then
              return status, body, headers
            end

            if headers then
              headers["Has-Headers"] = "true"

            else
              headers = { ["Has-Headers"] = "false" }
            end

            local new_body = {
              status = status,
              error = false,
              message = body.message,
            }
            if status == 429 then
               new_body.error = true
               new_body.message = "Kong API Quota exceeded!"
            end

            if status == 401 then
              new_body.error = true
            end

            return status, new_body, headers
          end
        ]]
        assert(bp.plugins:insert {
          name = "exit-transformer",
          route = { id = route23.id },
          config = { functions = { function_body_headers } },
        })
        assert(bp.plugins:insert(
          build_plugin(route23.id, MOCK_RATE, 3, 1, nil, nil, redis_configuration)
        ))

        local route_for_consumer_group = assert(bp.routes:insert {
          name = "test_consumer_groups",
          hosts = { "testconsumergroup.test"},
        })

        local route_for_consumer_group_no_config = assert(bp.routes:insert {
          name = "test_consumer_groups_no_config",
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
            route_for_consumer_group.id, 5, MOCK_ORIGINAL_LIMIT, 2, nil,
            nil, redis_configuration, {
              namespace = "Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu",
              enforce_consumer_groups = true,
              consumer_groups = { "test_consumer_group" }
            }
          )
        ))

        assert(bp.plugins:insert(
          build_plugin(
            route_for_consumer_group_no_config.id, 5, MOCK_ORIGINAL_LIMIT, 2, nil,
            nil, {
              host = REDIS_HOST,
              port = REDIS_PORT,
              database = REDIS_DATABASE,
              password = REDIS_PASSWORD_VALID,
            }, {
              namespace = "Dk1krkTWBqmcKEQVW5cQNLgikuKygjnu",
              enforce_consumer_groups = true,
              consumer_groups = { "test_consumer_group_no_config" }
            }
          )
        ))


        local route_for_custom_response = bp.routes:insert {
          hosts = { "route_for_custom_response.test" },
        }

        assert(bp.plugins:insert(
          build_plugin(
            route_for_custom_response.id, 5, MOCK_ORIGINAL_LIMIT, 2, nil,
            nil, redis_configuration, {
              error_code = 405,
              error_message = "Testing",
            }
          )
        ))

        assert(helpers.start_kong{
          plugins = "rate-limiting-advanced,key-auth,exit-transformer",
          nginx_conf = "spec/fixtures/custom_nginx.template",
          database = strategy ~= "off" and strategy or nil,
          db_update_frequency = 0.1,
          prefix = "node1",
          declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
          nginx_worker_processes = 1,
        })


        assert(helpers.start_kong{
          plugins = "rate-limiting-advanced,key-auth,exit-transformer",
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

        remove_redis_user(policy)
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

        -- traditional mode but use redis strategy
        if policy ~= "redis" then
          it("sync counters in all nodes after PATCH", function()
            local window_size = plugin15.config.window_size[1]
            local limit = plugin15.config.limit[1]

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

            --[= succeed locally but unstable on CI/CD
            -- Hit node2 so the sync timer starts
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

            -- Wait for counters to sync node2: 0.1+0.1
            ngx_sleep(plugin15.config.sync_rate + 0.1)

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
              path = "/plugins/" .. plugin15.id,
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
            ngx_sleep(plugin15.config.window_size[1] + 1)
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

            --[= succeed locally but unsable on CI/CD
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
            ngx_sleep(plugin15.config.sync_rate + 0.1)

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
              path = "/plugins/" .. plugin3.id,
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

            --[= flaky on CI/CD but succeed locally
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
              path = "/plugins/" .. plugin5.id,
            })
            assert.res_status(204, res)

            assert.logfile("node1/logs/error.log").has.no.line("[error]", true)
            assert.logfile("node2/logs/error.log").has.no.line("[error]", true)
            --[= flaky on CI/CD but succeed locally
            helpers.pwait_until(function()
              assert.logfile("node1/logs/error.log").has.line("killing 046F4FC717A147C2A446A4BEA763CF1E", true, 20)
            end, 60)
            helpers.pwait_until(function()
              assert.logfile("node2/logs/error.log").has.line("killing 046F4FC717A147C2A446A4BEA763CF1E", true, 20)
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
                name = "rate-limiting-advanced",
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

        it("shares limit data in the same namespace", function()
          wait_for_next_fixed_window(MOCK_RATE)
          -- decrement the counters in route4
          for i = 1, 3 do
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test4.test"
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            assert.are.same(3, tonumber(res.headers["x-ratelimit-limit-3"]))
            assert.are.same(3, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(3 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
            assert.are.same(3 - i, tonumber(res.headers["ratelimit-remaining"]))
            assert.is_true(tonumber(res.headers["ratelimit-reset"]) > 0)
            assert.is_nil(res.headers["retry-after"])
          end

          -- access route5, which shares the same namespace
          proxy_client = helpers.proxy_client()
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test5.test"
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
          local window_size = plugin6.config.window_size[1]
          local limit = plugin6.config.limit[1]
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

            -- Using a different key of the same consumer works
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey333",
              headers = {
                ["Host"] = "test3.test"
              }
            })
            assert.res_status(200, res)
            proxy_client:close()

            assert.is_truthy(res.headers["x-ratelimit-limit-3"])
            assert.is_truthy(res.headers["ratelimit-limit"])
            assert.is_truthy(res.headers["x-ratelimit-remaining-3"])
            assert.is_truthy(res.headers["ratelimit-remaining"])
            assert.is_truthy(res.headers["ratelimit-reset"])
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

            local body_json = cjson.decode((res:read_body()))
            assert.is_true(body_json.error)
            assert.equal("true", res.headers["has-headers"])
            assert.same("Kong API Quota exceeded!", body_json.message)

            if proxy_client then proxy_client:close() end
          end)
        end)

        if strategy ~= "off" then
        describe("With consumer group", function()
          local name = "overrides with group configurations when consumer is in group"
          if policy == "redis" then
            name = "#flaky-candidate " .. name
          end
          it(name, function()
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikeycg",
              headers = {
                ["Host"] = "testconsumergroup.test"
              }
            })
            assert.res_status(200, res)
            assert.are.same(MOCK_GROUP_LIMIT, tonumber(res.headers["x-ratelimit-limit-10"]))
            assert.are.same(MOCK_GROUP_LIMIT, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(MOCK_GROUP_LIMIT - 1, tonumber(res.headers["x-ratelimit-remaining-10"]))
            assert.are.same(MOCK_GROUP_LIMIT - 1, tonumber(res.headers["ratelimit-remaining"]))
          end)
          name = "should not use group configurations when consumer is not in group"
          if policy == "redis" then
            name = "#flaky-candidate " .. name
          end
          it(name, function()
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "testconsumergroup.test"
              }
            })
            assert.res_status(200, res)
            assert.are.same(MOCK_ORIGINAL_LIMIT, tonumber(res.headers["x-ratelimit-limit-5"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT - 1, tonumber(res.headers["x-ratelimit-remaining-5"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT - 1, tonumber(res.headers["ratelimit-remaining"]))
          end)
          name = "should not change limit for plugin instances of the same consumer if group not enforced"
          if policy == "redis" then
            name = "#flaky-candidate " .. name
          end
          it(name, function()
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikeycg",
              headers = {
                ["Host"] = "test3.test"
              }
            })
            assert.res_status(200, res)
            assert.are.same(MOCK_ORIGINAL_LIMIT, tonumber(res.headers["x-ratelimit-limit-3"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT - 1, tonumber(res.headers["x-ratelimit-remaining-3"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT - 1, tonumber(res.headers["ratelimit-remaining"]))
          end)

          name = "should use default configs if consumer group is enforced but no config value is provided"
          if policy == "redis" then
            name = "#flaky-candidate " .. name
          end
          it(name, function()
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikeycgnoconfig",
              headers = {
                ["Host"] = "testconsumergroupnoconfig.test"
              }
            })

            assert.res_status(200, res)
            assert.are.same(MOCK_ORIGINAL_LIMIT, tonumber(res.headers["x-ratelimit-limit-5"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT - 1, tonumber(res.headers["x-ratelimit-remaining-5"]))
            assert.are.same(MOCK_ORIGINAL_LIMIT - 1, tonumber(res.headers["ratelimit-remaining"]))
          end)
        end)
        end
      end)
      describe("With identifier", function()
        describe("not set, use default `consumer`", function()
          it("should not block consumer1 when limit exceed for consumer2", function()
            for i = 1, 6 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get?apikey=apikey123",
                headers = {
                  ["Host"] = "test7.test"
                }
              })
              local body = assert.res_status(200, res)
              proxy_client:close()

              local json = cjson.decode(body)
              assert.are.same(consumer2.id, json.headers["x-consumer-id"])
              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
              assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            end

            -- Additonal request, while limit is 6/window, for
            -- consumer2 should be blocked
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test7.test"
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
            local retry_after = tonumber(res.headers["retry-after"])

            -- consumer1 should still be able to make request as
            -- limit is set by consumer not IP
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey122",
              headers = {
                ["Host"] = "test7.test"
              }
            })
            local body = assert.res_status(200, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.are.same(consumer1.id, json.headers["x-consumer-id"])

            -- wait a bit longer than our retry window size for the rate limited consumer
            ngx_sleep(retry_after + 1)
          end)
        end)
        describe("set to `ip`", function()
          it("should block consumer1 when consumer2 breach limit", function()
            for i = 1, 6 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get?apikey=apikey123",
                headers = {
                  ["Host"] = "test8.test"
                }
              })
              local body = assert.res_status(200, res)
              proxy_client:close()

              local json = cjson.decode(body)
              assert.are.same(consumer2.id, json.headers["x-consumer-id"])
              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
              assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            end

            -- Additonal request, while limit is 6/window, for consumer2
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test8.test"
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)

            -- consumer1 should not be able to make request as
            -- limit is set by IP
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey122",
              headers = {
                ["Host"] = "test8.test"
              }
            })
            assert.res_status(429, res)
            proxy_client:close()
          end)
        end)
        describe("set to `#service`", function()
          it("should be global to service, and independent between services", function()
            wait_for_next_fixed_window(plugin10.config.window_size[1])
            for i = 1, 6 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get",
                headers = {
                  ["Host"] = "test10.test"
                }
              })
              assert.res_status(200, res)
              proxy_client:close()
            end

            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test10.test"
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)

            wait_for_next_fixed_window(MOCK_RATE)
            -- service11 should still be able to make request as
            -- limit is set by service
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test11.test"
              }
            })
            assert.res_status(200, res)
            proxy_client:close()
          end)
          it("should be global to service, and share rate between routes in service", function()
            local window_size = 10
            for i = 0, 2 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get",
                headers = {
                  ["Host"] = "shared-service-test-1.test"
                }
              })
              assert.res_status(200, res)
              proxy_client:close()

              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-" .. window_size]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))

              assert.are.same(6 - ((i * 2) + 1), tonumber(res.headers["x-ratelimit-remaining-" .. window_size]))
              assert.are.same(6 - ((i * 2) + 1), tonumber(res.headers["ratelimit-remaining"]))

              proxy_client = helpers.proxy_client()
              res = assert(proxy_client:send {
                method = "GET",
                path = "/get",
                headers = {
                  ["Host"] = "shared-service-test-2.test"
                }
              })
              assert.res_status(200, res)
              proxy_client:close()

              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-" .. window_size]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - ((i * 2) + 2), tonumber(res.headers["x-ratelimit-remaining-" .. window_size]))
              assert.are.same(6 - ((i * 2) + 2), tonumber(res.headers["ratelimit-remaining"]))
            end

            -- Ensure both routes in shared service have exceeded their limit
            local retry_after
            for i = 1, 2 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get",
                headers = {
                  ["Host"] = "shared-service-test-" .. i .. ".test"
                }
              })
              local body = assert.res_status(429, res)
              proxy_client:close()

              local json = cjson.decode(body)
              assert.same({ message = "API rate limit exceeded" }, json)
              retry_after = tonumber(res.headers["retry-after"])
            end

            -- wait a bit longer than our retry window size
            ngx_sleep(retry_after + 1)

            -- Ensure both routes in shared service have not exceeded their limit
            for i = 1, 2 do
              -- Additonal request, sliding window is 0 < rate <= limit
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get",
                headers = {
                  ["Host"] = "shared-service-test-" .. i .. ".test"
                }
              })
              assert.res_status(200, res)
              proxy_client:close()

              local rate = tonumber(res.headers["x-ratelimit-remaining-" .. window_size])
              assert.is_true(0 < rate and rate <= 6)
              rate = tonumber(res.headers["ratelimit-remaining"])
              assert.is_true(0 < rate and rate <= 6)
            end
          end)
        end)
        describe("set to `header` + customers use the same headers", function()
          it("should block consumer1 when consumer2 breach limit", function()
            for i = 1, 6 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get?apikey=apikey123",
                headers = {
                  ["Host"] = "test12.test",
                  ["x-email-address"] = "test1@example.com",
                }
              })
              local body = assert.res_status(200, res)
              proxy_client:close()

              local json = cjson.decode(body)
              assert.are.same(consumer2.id, json.headers["x-consumer-id"])
              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
              assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            end

            -- Additonal request, while limit is 6/window, for consumer2
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test12.test",
                ["x-email-address"] = "test1@example.com",
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)

            -- consumer1 should not be able to make request as limit is set by
            -- header and both consumers use the same header values
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey122",
              headers = {
                ["Host"] = "test12.test",
                ["x-email-address"] = "test1@example.com",
              }
            })
            assert.res_status(429, res)
            proxy_client:close()
          end)
        end)
        describe("set to `header` + customers use different headers", function()
          it("should not block consumer1 when consumer2 breach limit", function()
            for i = 1, 6 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/get?apikey=apikey123",
                headers = {
                  ["Host"] = "test12.test",
                  ["x-email-address"] = "test2@example.com"
                }
              })
              local body = assert.res_status(200, res)
              proxy_client:close()

              local json = cjson.decode(body)
              assert.are.same(consumer2.id, json.headers["x-consumer-id"])
              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
              assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            end

            -- Additonal request, while limit is 6/window, for consumer2
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test12.test",
                ["x-email-address"] = "test2@example.com",
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)

            -- consumer1 should still be able to make request as limit is set by -- header and both consumers use different header values
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/get?apikey=apikey122",
              headers = {
                ["Host"] = "test12.test",
                ["x-email-address"] = "test3@example.com",
              }
            })
            local body = assert.res_status(200, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.are.same(consumer1.id, json.headers["x-consumer-id"])
          end)
        end)

        describe("set to `path`", function()
          it("blocks after 6 requests on same path", function()
            for i = 1, 6 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
                method = "GET",
                path = "/status/200",
                headers = {
                  ["Host"] = "test19.test",
                }
              })
              assert.res_status(200, res)
              proxy_client:close()

              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-5"]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-5"]))
              assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            end

            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/status/200",
              headers = {
                ["Host"] = "test19.test",
              }
            })
            local body = assert.res_status(429, res)
            proxy_client:close()

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)

            -- allow on a different path
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/status/201",
              headers = {
                ["Host"] = "test19.test",
              }
            })
            assert.res_status(201, res)
            proxy_client:close()

            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-5"]))
            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-5"]))
            assert.are.same(5, tonumber(res.headers["ratelimit-remaining"]))
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
      describe("rate-limiting-advanced Hybrid Mode with strategy #" .. strategy .. "#", function()
        local plugin2, plugin4, plugin20, plugin21
        local proxy_client

        lazy_setup(function()
          redis.flush_redis(REDIS_HOST, REDIS_PORT, REDIS_DATABASE, nil, nil)
          add_redis_user(policy)

          local bp = helpers.get_db_utils(strategy ~= "off" and strategy or nil,
                                          nil, {"rate-limiting-advanced"})

          local service16 = assert(bp.services:insert {
            name = "svc16",
            url = "http://127.0.0.1:" .. HTTP_SERVER_PORT_16,
          })
          local route16 = assert(bp.routes:insert {
            name = "test-16",
            hosts = { "test16.test" },
            service = { id = service16.id },
          })
          plugin2 = assert(bp.plugins:insert(
            build_plugin_fn("redis")(
              route16.id, 5, 1, 0.1, nil,
              nil, redis_configuration,
              { header_name = "x-email-address", identifier = "header", namespace = "ED83AE45-887D-4A73-8AC8-5120C0D7E6E9" }
            )
          ))

          local route18 = assert(bp.routes:insert {
            name = "test-18",
            hosts = { "test18.test" },
          })
          plugin4 = assert(bp.plugins:insert(
            build_plugin_fn("redis")(
              route18.id, 5, 6, 1, nil,
              nil, redis_configuration,
              { namespace = "Ck1krkTWBqmcKEQVW5cQNLgikuKygjnu" }
            )
          ))

          local service20 = assert(bp.services:insert {
            name = "svc20",
            url = "http://127.0.0.1:" .. HTTP_SERVER_PORT_20,
          })
          local route20 = assert(bp.routes:insert {
            name = "test-20",
            hosts = { "test20.test" },
            service = { id = service20.id }
          })
          plugin20 = assert(bp.plugins:insert(
            build_plugin_fn("local")(
              route20.id, 5, 2, -1, nil,
              nil, nil, { namespace = "7674e5db-0dfe-4c95-af4a-b71f61d4f9dd" }
            )
          ))

          local route21 = assert(bp.routes:insert {
            name = "test-21",
            hosts = { "test21.test" },
          })
          plugin21 = assert(bp.plugins:insert(
            build_plugin_fn("local")(
              route21.id, 5, 2, -1, nil,
              nil, nil, { namespace = "9a34c29b-1d3b-38e5-2ef0-a82a19d71682" }
            )
          ))

          assert(helpers.start_kong({
            plugins = "rate-limiting-advanced,key-auth",
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
            plugins = "rate-limiting-advanced,key-auth",
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
            plugins = "rate-limiting-advanced,key-auth",
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

        it("we are NOT leaking any timers after DELETE on hybrid mode", function()
          helpers.clean_logfile("dp1/logs/error.log")

          -- DELETE the plugin
          local res = assert(helpers.admin_client(nil, 9103):send {
            method = "DELETE",
            path = "/plugins/" .. plugin4.id,
          })
          assert.res_status(204, res)

          helpers.wait_for_file_contents("dp1/logs/error.log")
          helpers.pwait_until(function()
            assert.logfile("dp1/logs/error.log").has.line("killing Ck1krkTWBqmcKEQVW5cQNLgikuKygjnu", true, 20)
          end, 180)
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
              name = "rate-limiting-advanced",
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
            path = "/plugins/" .. plugin21.id,
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

        it("local strategy works", function()
          local mock = http_mock.new(HTTP_SERVER_PORT_20)
          mock:start()
          finally(function()
            mock:stop(true)
          end)
          local window_size = plugin20.config.window_size[1]
          local limit = plugin20.config.limit[1]
          for i = 1, limit do
            ngx_sleep(1)
            proxy_client = helpers.proxy_client(nil, PROXY_PORT)
            local res = assert(proxy_client:send {
              method = "GET",
              path = "/",
              headers = {
                ["Host"] = "test20.test",
              }
            })
            io.read()
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

          -- Additonal request on DP 1, while limit is 2/window
          proxy_client = helpers.proxy_client(nil, PROXY_PORT)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
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

          -- Request on DP 2, while limit is 2/window
          ngx_sleep(1)
          proxy_client = helpers.proxy_client(nil, 9104)
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {
              ["Host"] = "test20.test",
            }
          })
          assert.res_status(200, res)
          proxy_client:close()
          mock.eventually:has_one_without_error()
        end)

        it("sync counters in all DP nodes after PATCH", function()
          local mock = http_mock.new(HTTP_SERVER_PORT_16)
          mock:start()
          finally(function()
            mock:stop()
          end)

          local window_size = plugin2.config.window_size[1]
          local limit = plugin2.config.limit[1]

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

          --[= succeed locally but unsable on CI/CD
           -- Wait for counters to sync ON DP 2: 0.1+0.1
           ngx_sleep(plugin2.config.sync_rate + 0.1)

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
            path = "/plugins/" .. plugin2.id,
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
          ngx_sleep(plugin2.config.window_size[1] + 1)
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

          --[= succeed locally but unstable on CI/CD
          -- Wait for counters to sync ON DP 1: 0.1+0.1
          ngx_sleep(plugin2.config.sync_rate + 0.1)

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
  local PLUGIN_NAME = "rate-limiting-advanced"
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
            - rla.test
            paths:
            - /anything
            plugins:
            - name: %s
              config:
                namespace: rla
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
