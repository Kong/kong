local helpers        = require "spec.helpers"
local timestamp      = require "kong.tools.timestamp"
local cjson          = require "cjson"


local REDIS_HOST     = "127.0.0.1"
local REDIS_PORT     = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 1


local SLEEP_TIME     = 1


local fmt = string.format


local proxy_client = helpers.proxy_client


local function wait(second_offset)
  -- If the minute elapses in the middle of the test, then the test will
  -- fail. So we give it this test 30 seconds to execute, and if the second
  -- of the current minute is > 30, then we wait till the new minute kicks in
  local current_second = timestamp.get_timetable().sec
  if current_second > (second_offset or 0) then
    ngx.sleep(60 - current_second)
  end
end


local function flush_redis()
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(2000)
  local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
  if not ok then
    error("failed to connect to Redis: " .. err)
  end

  if REDIS_PASSWORD and REDIS_PASSWORD ~= "" then
    local ok, err = red:auth(REDIS_PASSWORD)
    if not ok then
      error("failed to connect to Redis: " .. err)
    end
  end

  local ok, err = red:select(REDIS_DATABASE)
  if not ok then
    error("failed to change Redis database: " .. err)
  end

  red:flushall()
  red:close()
end


for _, strategy in helpers.each_strategy() do
  for _, policy in ipairs({"local", "cluster", "redis"}) do
    describe(fmt("#flaky Plugin: rate-limiting (access) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local db
      local dao

      setup(function()
        helpers.kill_all()
        flush_redis()

        bp, db, dao = helpers.get_db_utils(strategy)

        local consumer1 = bp.consumers:insert {
          custom_id = "provider_123",
        }

        bp.keyauth_credentials:insert {
          key      = "apikey122",
          consumer = { id = consumer1.id },
        }

        local consumer2 = bp.consumers:insert {
          custom_id = "provider_124",
        }

        bp.keyauth_credentials:insert {
          key      = "apikey123",
          consumer = { id = consumer2.id },
        }

        bp.keyauth_credentials:insert {
          key      = "apikey333",
          consumer = { id = consumer2.id },
        }

        local route1 = bp.routes:insert {
          hosts = { "test1.com" },
        }

        bp.rate_limiting_plugins:insert({
          route = { id = route1.id },
          config = {
            policy         = policy,
            minute         = 6,
            fault_tolerant = false,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
          }
        })

        local route2 = bp.routes:insert {
          hosts      = { "test2.com" },
        }

        bp.rate_limiting_plugins:insert({
          route = { id = route2.id },
          config = {
            minute         = 3,
            hour           = 5,
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
          }
        })

        local route3 = bp.routes:insert {
          hosts = { "test3.com" },
        }

        bp.plugins:insert {
          name     = "key-auth",
          route = { id = route3.id },
        }

        bp.rate_limiting_plugins:insert({
          route = { id = route3.id },
          config = {
            minute         = 6,
            limit_by       = "credential",
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
          }
        })

        bp.rate_limiting_plugins:insert({
          route = { id = route3.id },
          consumer = { id = consumer1.id },
          config      = {
            minute         = 8,
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE
          }
        })

        local route4 = bp.routes:insert {
          hosts = { "test4.com" },
        }

        bp.plugins:insert {
          name     = "key-auth",
          route = { id = route4.id },
        }

        bp.rate_limiting_plugins:insert({
          route = { id = route4.id },
          consumer = { id = consumer1.id },
          config           = {
            minute         = 6,
            fault_tolerant = true,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
          },
        })

        local route5 = bp.routes:insert {
          hosts = { "test5.com" },
        }

        bp.rate_limiting_plugins:insert({
          route = { id = route5.id },
          config = {
            policy              = policy,
            minute              = 6,
            hide_client_headers = true,
            fault_tolerant      = false,
            redis_host          = REDIS_HOST,
            redis_port          = REDIS_PORT,
            redis_password      = REDIS_PASSWORD,
            redis_database      = REDIS_DATABASE,
          },
        })

        local route6 = bp.routes:insert {
          hosts = { "test6.com" },
        }

        bp.rate_limiting_plugins:insert({
          route_id = route6.id,
          config = {
            limit_by            = "key",
            key_name            = "token",
            key_in_body         = true,
            policy              = policy,
            minute              = 6,
            fault_tolerant      = false,
            redis_host          = REDIS_HOST,
            redis_port          = REDIS_PORT,
            redis_password      = REDIS_PASSWORD,
            redis_database      = REDIS_DATABASE,
          },
        })

        local service = bp.services:insert()
        bp.routes:insert {
          hosts = { "test-service1.com" },
          service = service,
        }
        bp.routes:insert {
          hosts = { "test-service2.com" },
          service = service,
        }

        bp.rate_limiting_plugins:insert({
          service = { id = service.id },
          config = {
            policy         = policy,
            minute         = 6,
            fault_tolerant = false,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
          }
        })

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)


      teardown(function()
        helpers.stop_kong()
        assert(db:truncate())
      end)

      before_each(function()
        wait(3)
      end)

      describe("Without authentication (IP address)", function()
        it("blocks if exceeding limit", function()
          for i = 1, 6 do
            local res = proxy_client():get("/status/200", {
              headers = { Host = "test1.com" },
            })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          end

          -- Additonal request, while limit is 6/minute
          local res = proxy_client():get("/status/200", {
            headers = { Host = "test1.com" },
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
        end)

        it("counts against the same service register from different routes", function()
          for i = 1, 3 do
            local res = proxy_client():get("/status/200", {
              headers = { Host = "test-service1.com" },
            })
            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          end

          for i = 4, 6 do
            local res = proxy_client():get("/status/200", {
              headers = { Host = "test-service2.com" },
            })
            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          end

          -- Additonal request, while limit is 6/minute
          local res = proxy_client():get("/status/200", {
            headers = { Host = "test-service1.com" },
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
        end)

        it("handles multiple limits", function()
          local limits = {
            minute = 3,
            hour   = 5
          }

          for i = 1, 3 do
            local res = proxy_client():get("/status/200", {
              headers = { Host = "test2.com" },
            })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(limits.minute, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(limits.minute - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            assert.are.same(limits.hour, tonumber(res.headers["x-ratelimit-limit-hour"]))
            assert.are.same(limits.hour - i, tonumber(res.headers["x-ratelimit-remaining-hour"]))
          end

          local res = proxy_client():get("/status/200", {
            path    = "/status/200",
            headers = { Host = "test2.com" },
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          assert.are.equal(2, tonumber(res.headers["x-ratelimit-remaining-hour"]))
          assert.are.equal(0, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        end)
      end)
      describe("With authentication", function()
        describe("API-specific plugin", function()
          it("blocks if exceeding limit", function()
            for i = 1, 6 do
              local res = proxy_client():get("/status/200?apikey=apikey123", {
                headers = { Host = "test3.com" },
              })

              ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

              assert.res_status(200, res)
              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            end

            -- Third query, while limit is 2/minute
            local res = proxy_client():get("/status/200?apikey=apikey123", {
              headers = { Host = "test3.com" },
            })
            local body = assert.res_status(429, res)
            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)

            -- Using a different key of the same consumer works
            local res = proxy_client():get("/status/200?apikey=apikey333", {
              headers = { Host = "test3.com" },
            })
            assert.res_status(200, res)
          end)
        end)
        describe("Plugin customized for specific consumer and route", function()
          it("blocks if exceeding limit", function()
            for i = 1, 8 do
              local res = proxy_client():get("/status/200?apikey=apikey122", {
                headers = { Host = "test3.com" },
              })

              ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

              assert.res_status(200, res)
              assert.are.same(8, tonumber(res.headers["x-ratelimit-limit-minute"]))
              assert.are.same(8 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            end

            local res = proxy_client():get("/status/200?apikey=apikey122", {
              headers = { Host = "test3.com" },
            })
            local body = assert.res_status(429, res)
            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
          end)
          it("blocks if the only rate-limiting plugin existing is per consumer and not per API", function()
            for i = 1, 6 do
              local res = proxy_client():get("/status/200?apikey=apikey122", {
                headers = { Host = "test4.com" },
              })

              ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

              assert.res_status(200, res)
              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            end

            local res = proxy_client():get("/status/200?apikey=apikey122", {
              headers = { Host = "test4.com" },
            })
            local body = assert.res_status(429, res)
            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
          end)
        end)
      end)

      describe("Config with hide_client_headers", function()
        it("does not send rate-limit headers when hide_client_headers==true", function()
          local res = proxy_client():get("/status/200", {
            headers = { Host = "test5.com" },
          })

          assert.res_status(200, res)
          assert.is_nil(res.headers["x-ratelimit-limit-minute"])
          assert.is_nil(res.headers["x-ratelimit-remaining-minute"])
        end)
      end)

      describe("Config with limit by key", function()
        it("should limit by a key", function()
          for i = 1, 6 do
            local res = proxy_client():get("/status/200?token=t1", { headers = { Host = "test6.com" } })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          end

          local res = proxy_client():get("/status/200?token=t1", { headers = { Host = "test6.com" } })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)

          -- Switch to other key, new counter will be used
          local res = proxy_client():get("/status/200?token=t2", { headers = { Host = "test6.com" } })
          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        end)

        it("should read key from body", function()
          for i = 1, 6 do
            local res = proxy_client():get("/status/200", {
              headers = { Host = "test6.com", ["Content-Type"] = "application/json" },
              body = { token = "t1" }
            })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          end

          local res = proxy_client():get("/status/200", {
            headers = { Host = "test6.com", ["Content-Type"] = "application/json" },
            body = { token = "t1" }
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)

          -- Switch to other key, new counter will be used
          local res = proxy_client():get("/status/200", {
            headers = { Host = "test6.com", ["Content-Type"] = "application/json" },
            body = { token = "t2" }
          })
          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        end)
      end)

      if policy == "cluster" then
        describe("Fault tolerancy", function()

          before_each(function()
            helpers.kill_all()

            assert(db:truncate())
            dao:truncate_tables()

            local route1 = bp.routes:insert {
              hosts = { "failtest1.com" },
            }

            bp.rate_limiting_plugins:insert {
              route = { id = route1.id },
              config   = { minute = 6, fault_tolerant = false }
            }

            local route2 = bp.routes:insert {
              hosts = { "failtest2.com" },
            }

            bp.rate_limiting_plugins:insert {
              name     = "rate-limiting",
              route = { id = route2.id },
              config   = { minute = 6, fault_tolerant = true },
            }

            assert(helpers.start_kong({
              database   = strategy,
              nginx_conf = "spec/fixtures/custom_nginx.template",
            }))
          end)

          teardown(function()
            helpers.kill_all()
            assert(db:truncate())
          end)

          it("does not work if an error occurs", function()
            local res = proxy_client():get("/status/200", {
              headers = { Host = "failtest1.com" },
            })
            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))

            -- Simulate an error on the database
            assert(dao.db:drop_table("ratelimiting_metrics"))

            -- Make another request
            local res = proxy_client():get("/status/200", {
              headers = { Host = "failtest1.com" },
            })
            local body = assert.res_status(500, res)
            local json = cjson.decode(body)
            assert.same({ message = "An unexpected error occurred" }, json)
          end)
          it("keeps working if an error occurs", function()
            local res = proxy_client():get("/status/200", {
              headers = { Host = "failtest2.com" },
            })
            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))

            -- Simulate an error on the database
            assert(dao.db:drop_table("ratelimiting_metrics"))

            -- Make another request
            local res = proxy_client():get("/status/200", {
              headers = { Host = "failtest2.com" },
            })
            assert.res_status(200, res)
            assert.falsy(res.headers["x-ratelimit-limit-minute"])
            assert.falsy(res.headers["x-ratelimit-remaining-minute"])
          end)
        end)

      elseif policy == "redis" then
        describe("Fault tolerancy", function()

          before_each(function()
            helpers.kill_all()

            local service1 = bp.services:insert()

            local route1 = bp.routes:insert {
              hosts      = { "failtest3.com" },
              protocols  = { "http", "https" },
              service    = service1
            }

            bp.rate_limiting_plugins:insert {
              route = { id = route1.id },
              config  = { minute = 6, policy = policy, redis_host = "5.5.5.5", fault_tolerant = false },
            }

            local service2 = bp.services:insert()

            local route2 = bp.routes:insert {
              hosts      = { "failtest4.com" },
              protocols  = { "http", "https" },
              service    = service2
            }

            bp.rate_limiting_plugins:insert {
              name   = "rate-limiting",
              route = { id = route2.id },
              config = { minute = 6, policy = policy, redis_host = "5.5.5.5", fault_tolerant = true },
            }

            assert(helpers.start_kong({
              database   = strategy,
              nginx_conf = "spec/fixtures/custom_nginx.template",
            }))
          end)

          it("does not work if an error occurs", function()
            -- Make another request
            local res = proxy_client():get("/status/200", {
              headers = { Host = "failtest3.com" },
            })
            local body = assert.res_status(500, res)
            local json = cjson.decode(body)
            assert.same({ message = "An unexpected error occurred" }, json)
          end)
          it("keeps working if an error occurs", function()
            -- Make another request
            local res = proxy_client():get("/status/200", {
              headers = { Host = "failtest4.com" },
            })
            assert.res_status(200, res)
            assert.falsy(res.headers["x-ratelimit-limit-minute"])
            assert.falsy(res.headers["x-ratelimit-remaining-minute"])
          end)
        end)
      end

      describe("Expirations", function()
        local route

        setup(function()
          helpers.stop_kong()

          local bp = helpers.get_db_utils(strategy)

          route = bp.routes:insert {
            hosts = { "expire1.com" },
          }

          bp.rate_limiting_plugins:insert {
            route = { id = route.id },
            config   = {
              minute         = 6,
              policy         = policy,
              redis_host     = REDIS_HOST,
              redis_port     = REDIS_PORT,
              redis_password = REDIS_PASSWORD,
              fault_tolerant = false,
              redis_database = REDIS_DATABASE,
            },
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))
        end)

        describe("expires a counter", function()
          local res = proxy_client():get("/status/200", {
            headers = { Host = "expire1.com" },
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))

          ngx.sleep(61) -- Wait for counter to expire

          local res = proxy_client():get("/status/200", {
            headers = { Host = "expire1.com" }
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        end)
      end)
    end)

    describe(fmt("#flaky Plugin: rate-limiting (access - global for single consumer) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local db

      setup(function()
        helpers.kill_all()
        flush_redis()
        bp, db = helpers.get_db_utils(strategy)

        local consumer = bp.consumers:insert {
          custom_id = "provider_125",
        }

        bp.key_auth_plugins:insert()

        bp.keyauth_credentials:insert {
          key      = "apikey125",
          consumer = { id = consumer.id },
        }

        -- just consumer, no no route or service
        bp.rate_limiting_plugins:insert({
          consumer = { id = consumer.id },
          config = {
            limit_by       = "credential",
            policy         = policy,
            minute         = 6,
            fault_tolerant = false,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
          }
        })

        for i = 1, 6 do
          bp.routes:insert({ hosts = { fmt("test%d.com", i) } })
        end

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.kill_all()
        assert(db:truncate())
      end)

      it("blocks when the consumer exceeds their quota, no matter what service/route used", function()
        for i = 1, 6 do
          local res = proxy_client():get("/status/200?apikey=apikey125", {
            headers = { Host = fmt("test%d.com", i) },
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        end

        -- Additonal request, while limit is 6/minute
        local res = proxy_client():get("/status/200?apikey=apikey125", {
          headers = { Host = "test1.com" },
        })
        local body = assert.res_status(429, res)
        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded" }, json)
      end)
    end)

    describe(fmt("#flaky Plugin: rate-limiting (access - global) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local db

      setup(function()
        helpers.kill_all()
        flush_redis()
        bp, db = helpers.get_db_utils(strategy)

        -- global plugin (not attached to route, service or consumer)
        bp.rate_limiting_plugins:insert({
          config = {
            policy         = policy,
            minute         = 6,
            fault_tolerant = false,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
          }
        })

        for i = 1, 6 do
          bp.routes:insert({ hosts = { fmt("test%d.com", i) } })
        end

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.kill_all()
        assert(db:truncate())
      end)

      it("blocks if exceeding limit", function()
        for i = 1, 6 do
          local res = proxy_client():get("/status/200", {
            headers = { Host = fmt("test%d.com", i) },
          })

          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        end

        ngx.sleep(SLEEP_TIME)

        -- Additonal request, while limit is 6/minute
        local res = proxy_client():get("/status/200", {
          headers = { Host = "test1.com" },
        })
        local body = assert.res_status(429, res)
        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded" }, json)
      end)
    end)
  end
end


