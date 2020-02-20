local helpers        = require "spec.helpers"
local cjson          = require "cjson"


local REDIS_HOST     = helpers.redis_host
local REDIS_PORT     = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 1


local fmt = string.format
local proxy_client = helpers.proxy_client


-- This performs the test up to two times (and no more than two).
-- We are **not** retrying to "give it another shot" in case of a flaky test.
-- The reason why we allow for a single retry in this test suite is because
-- tests are dependent on the value of the current minute. If the minute
-- flips during the test (i.e. going from 03:43:59 to 03:44:00), the result
-- will fail. Since each test takes less than a minute to run, running it
-- a second time right after that failure ensures that another flip will
-- not occur. If the second execution failed as well, this means that there
-- was an actual problem detected by the test.
local function it_with_retry(desc, test)
  return it(desc, function(...)
    if not pcall(test, ...) then
      ngx.sleep(61 - (ngx.now() % 60))  -- Wait for minute to expire
      test(...)
    end
  end)
end


local function GET(url, opts, res_status)
  ngx.sleep(0.010)

  local client = proxy_client()
  local res, err  = client:get(url, opts)
  if not res then
    client:close()
    return nil, err
  end

  local body, err = assert.res_status(res_status, res)
  if not body then
    return nil, err
  end

  client:close()

  return res, body
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
  for _, policy in ipairs({ "local", "cluster", "redis" }) do
    describe(fmt("Plugin: rate-limiting (access) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local db

      lazy_setup(function()
        helpers.kill_all()
        flush_redis()

        bp, db = helpers.get_db_utils(strategy)

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

      lazy_teardown(function()
        helpers.stop_kong()
        assert(db:truncate())
      end)

      describe("Without authentication (IP address)", function()
        it_with_retry("blocks if exceeding limit", function()
          for i = 1, 6 do
            local res = GET("/status/200", {
              headers = { Host = "test1.com" },
            }, 200)

            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset >= 0)
          end

          -- Additonal request, while limit is 6/minute
          local res, body = GET("/status/200", {
            headers = { Host = "test1.com" },
          }, 429)

          assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
          assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))

          local retry = tonumber(res.headers["retry-after"])
          assert.equal(true, retry <= 60 and retry > 0)

          local reset = tonumber(res.headers["ratelimit-reset"])
          assert.equal(true, reset <= 60 and reset > 0)

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
        end)

        it_with_retry("counts against the same service register from different routes", function()
          for i = 1, 3 do
            local res = GET("/status/200", {
              headers = { Host = "test-service1.com" },
            }, 200)

            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset > 0)
          end

          for i = 4, 6 do
            local res = GET("/status/200", {
              headers = { Host = "test-service2.com" },
            }, 200)

            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset > 0)
          end

          -- Additonal request, while limit is 6/minute
          local res, body = GET("/status/200", {
            headers = { Host = "test-service1.com" },
          }, 429)

          assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
          assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))

          local retry = tonumber(res.headers["retry-after"])
          assert.equal(true, retry <= 60 and retry > 0)

          local reset = tonumber(res.headers["ratelimit-reset"])
          assert.equal(true, reset <= 60 and reset > 0)

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
        end)

        it_with_retry("handles multiple limits", function()
          local limits = {
            minute = 3,
            hour   = 5
          }

          for i = 1, 3 do
            local res = GET("/status/200", {
              headers = { Host = "test2.com" },
            }, 200)

            assert.are.same(limits.minute, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(limits.minute - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            assert.are.same(limits.hour, tonumber(res.headers["x-ratelimit-limit-hour"]))
            assert.are.same(limits.hour - i, tonumber(res.headers["x-ratelimit-remaining-hour"]))
            assert.are.same(limits.minute, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(limits.minute - i, tonumber(res.headers["ratelimit-remaining"]))
            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset > 0)
          end

          local res, body = GET("/status/200", {
            path    = "/status/200",
            headers = { Host = "test2.com" },
          }, 429)

          assert.are.same(limits.minute, tonumber(res.headers["ratelimit-limit"]))
          assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))
          assert.equal(2, tonumber(res.headers["x-ratelimit-remaining-hour"]))
          assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-minute"]))

          local retry = tonumber(res.headers["retry-after"])
          assert.equal(true, retry <= 60 and retry > 0)

          local reset = tonumber(res.headers["ratelimit-reset"])
          assert.equal(true, reset <= 60 and reset > 0)

          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
        end)
      end)
      describe("With authentication", function()
        describe("API-specific plugin", function()
          it_with_retry("blocks if exceeding limit", function()
            for i = 1, 6 do
              local res = GET("/status/200?apikey=apikey123", {
                headers = { Host = "test3.com" },
              }, 200)

              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
              local reset = tonumber(res.headers["ratelimit-reset"])
              assert.equal(true, reset <= 60 and reset > 0)
            end

            -- Third query, while limit is 2/minute
            local res, body = GET("/status/200?apikey=apikey123", {
              headers = { Host = "test3.com" },
            }, 429)

            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))

            local retry = tonumber(res.headers["retry-after"])
            assert.equal(true, retry <= 60 and retry > 0)

            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset > 0)

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)

            -- Using a different key of the same consumer works
            GET("/status/200?apikey=apikey333", {
              headers = { Host = "test3.com" },
            }, 200)
          end)
        end)
        describe("#flaky Plugin customized for specific consumer and route", function()
          it_with_retry("blocks if exceeding limit", function()
            for i = 1, 8 do
              local res = GET("/status/200?apikey=apikey122", {
                headers = { Host = "test3.com" },
              }, 200)

              assert.are.same(8, tonumber(res.headers["x-ratelimit-limit-minute"]))
              assert.are.same(8 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
              assert.are.same(8, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(8 - i, tonumber(res.headers["ratelimit-remaining"]))
              local reset = tonumber(res.headers["ratelimit-reset"])
              assert.equal(true, reset <= 60 and reset > 0)
            end

            local res, body = GET("/status/200?apikey=apikey122", {
              headers = { Host = "test3.com" },
            }, 429)

            assert.are.same(8, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))

            local retry = tonumber(res.headers["retry-after"])
            assert.equal(true, retry <= 60 and retry > 0)

            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset > 0)

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
          end)

          it_with_retry("blocks if the only rate-limiting plugin existing is per consumer and not per API", function()
            for i = 1, 6 do
              local res = GET("/status/200?apikey=apikey122", {
                headers = { Host = "test4.com" },
              }, 200)

              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
              assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
              assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
              local reset = tonumber(res.headers["ratelimit-reset"])
              assert.equal(true, reset <= 60 and reset > 0)
            end

            local res, body = GET("/status/200?apikey=apikey122", {
              headers = { Host = "test4.com" },
            }, 429)

            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))

            local retry = tonumber(res.headers["retry-after"])
            assert.equal(true, retry <= 60 and retry > 0)

            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset > 0)

            local json = cjson.decode(body)
            assert.same({ message = "API rate limit exceeded" }, json)
          end)
        end)
      end)

      describe("Config with hide_client_headers", function()
        it_with_retry("does not send rate-limit headers when hide_client_headers==true", function()
          local res = GET("/status/200", {
            headers = { Host = "test5.com" },
          }, 200)

          assert.is_nil(res.headers["x-ratelimit-limit-minute"])
          assert.is_nil(res.headers["x-ratelimit-remaining-minute"])
          assert.is_nil(res.headers["ratelimit-limit"])
          assert.is_nil(res.headers["ratelimit-remaining"])
          assert.is_nil(res.headers["ratelimit-reset"])
          assert.is_nil(res.headers["retry-after"])
        end)
      end)

      if policy == "cluster" then
        describe("#flaky Fault tolerancy", function()

          before_each(function()
            helpers.kill_all()

            assert(db:truncate())

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

          lazy_teardown(function()
            helpers.kill_all()
            assert(db:truncate())
          end)

          it_with_retry("does not work if an error occurs", function()
            local res = GET("/status/200", {
              headers = { Host = "failtest1.com" },
            }, 200)

            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(5, tonumber(res.headers["ratelimit-remaining"]))
            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset > 0)

            -- Simulate an error on the database
            assert(db.connector:query("DROP TABLE ratelimiting_metrics"))

            -- Make another request
            local _, body = GET("/status/200", {
              headers = { Host = "failtest1.com" },
            }, 500)

            local json = cjson.decode(body)
            assert.same({ message = "An unexpected error occurred" }, json)

            db:reset()
            bp, db = helpers.get_db_utils(strategy)
          end)

          it_with_retry("keeps working if an error occurs", function()
            local res = GET("/status/200", {
              headers = { Host = "failtest2.com" },
            }, 200)

            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))
            assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
            assert.are.same(5, tonumber(res.headers["ratelimit-remaining"]))
            local reset = tonumber(res.headers["ratelimit-reset"])
            assert.equal(true, reset <= 60 and reset > 0)

            -- Simulate an error on the database
            assert(db.connector:query("DROP TABLE ratelimiting_metrics"))

            -- Make another request
            local res = GET("/status/200", {
              headers = { Host = "failtest2.com" },
            }, 200)

            assert.falsy(res.headers["x-ratelimit-limit-minute"])
            assert.falsy(res.headers["x-ratelimit-remaining-minute"])
            assert.falsy(res.headers["ratelimit-limit"])
            assert.falsy(res.headers["ratelimit-remaining"])
            assert.falsy(res.headers["ratelimit-reset"])

            db:reset()
            bp, db = helpers.get_db_utils(strategy)
          end)
        end)

      elseif policy == "redis" then
        describe("#flaky Fault tolerancy", function()

          before_each(function()
            helpers.kill_all()

            assert(db:truncate())

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

          lazy_teardown(function()
            helpers.kill_all()
            assert(db:truncate())
          end)

          it_with_retry("does not work if an error occurs", function()
            -- Make another request
            local _, body = GET("/status/200", {
              headers = { Host = "failtest3.com" },
            }, 500)

            local json = cjson.decode(body)
            assert.same({ message = "An unexpected error occurred" }, json)
          end)

          it_with_retry("keeps working if an error occurs", function()
            local res = GET("/status/200", {
              headers = { Host = "failtest4.com" },
            }, 200)

            assert.falsy(res.headers["x-ratelimit-limit-minute"])
            assert.falsy(res.headers["x-ratelimit-remaining-minute"])
            assert.falsy(res.headers["ratelimit-limit"])
            assert.falsy(res.headers["ratelimit-remaining"])
            assert.falsy(res.headers["ratelimit-reset"])
          end)
        end)
      end

      describe("Expirations", function()
        local route

        lazy_setup(function()
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

        it_with_retry("#flaky expires a counter", function()
          local t = 61 - (ngx.now() % 60)

          local res = GET("/status/200", {
            headers = { Host = "expire1.com" },
          }, 200)

          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
          assert.are.same(5, tonumber(res.headers["ratelimit-remaining"]))
          local reset = tonumber(res.headers["ratelimit-reset"])
          assert.equal(true, reset <= 60 and reset > 0)

          ngx.sleep(t) -- Wait for minute to expire

          local res = GET("/status/200", {
            headers = { Host = "expire1.com" }
          }, 200)

          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
          assert.are.same(5, tonumber(res.headers["ratelimit-remaining"]))
          local reset = tonumber(res.headers["ratelimit-reset"])
          assert.equal(true, reset <= 60 and reset > 0)

        end)
      end)
    end)

    describe(fmt("Plugin: rate-limiting (access - global for single consumer) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local db

      lazy_setup(function()
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

      lazy_teardown(function()
        helpers.kill_all()
        assert(db:truncate())
      end)

      it_with_retry("blocks when the consumer exceeds their quota, no matter what service/route used", function()
        for i = 1, 6 do
          local res = GET("/status/200?apikey=apikey125", {
            headers = { Host = fmt("test%d.com", i) },
          }, 200)

          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
          assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
          local reset = tonumber(res.headers["ratelimit-reset"])
          assert.equal(true, reset <= 60 and reset > 0)
        end

        -- Additonal request, while limit is 6/minute
        local res, body = GET("/status/200?apikey=apikey125", {
          headers = { Host = "test1.com" },
        }, 429)

        assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
        assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))

        local retry = tonumber(res.headers["retry-after"])
        assert.equal(true, retry <= 60 and retry > 0)

        local reset = tonumber(res.headers["ratelimit-reset"])
        assert.equal(true, reset <= 60 and reset > 0)

        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded" }, json)
      end)
    end)

    describe(fmt("Plugin: rate-limiting (access - global for service) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local db

      lazy_setup(function()
        helpers.kill_all()
        flush_redis()
        bp, db = helpers.get_db_utils(strategy)

        -- global plugin (not attached to route, service or consumer)
        bp.rate_limiting_plugins:insert({
          config = {
            limit_by       = "service",
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

      lazy_teardown(function()
        helpers.kill_all()
        assert(db:truncate())
      end)

      it_with_retry("blocks if exceeding limit", function()
        for i = 1, 6 do
          local res = GET("/status/200", {
            headers = { Host = fmt("test%d.com", i) },
          }, 200)

          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
          assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
          local reset = tonumber(res.headers["ratelimit-reset"])
          assert.equal(true, reset <= 60 and reset > 0)
        end

        -- Additonal request, while limit is 6/minute
        local res, body = GET("/status/200", {
          headers = { Host = "test1.com" },
        }, 429)

        assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
        assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))

        local retry = tonumber(res.headers["retry-after"])
        assert.equal(true, retry <= 60 and retry > 0)

        local reset = tonumber(res.headers["ratelimit-reset"])
        assert.equal(true, reset <= 60 and reset > 0)

        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded" }, json)
      end)
    end)

    describe(fmt("Plugin: rate-limiting (access - global) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local db

      lazy_setup(function()
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

      lazy_teardown(function()
        helpers.kill_all()
        assert(db:truncate())
      end)

      it_with_retry("blocks if exceeding limit", function()
        for i = 1, 6 do
          local res = GET("/status/200", {
            headers = { Host = fmt("test%d.com", i) },
          }, 200)

          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
          assert.are.same(6 - i, tonumber(res.headers["ratelimit-remaining"]))
          local reset = tonumber(res.headers["ratelimit-reset"])
          assert.equal(true, reset <= 60 and reset > 0)
        end

        -- Additonal request, while limit is 6/minute
        local res, body = GET("/status/200", {
          headers = { Host = "test1.com" },
        }, 429)

        assert.are.same(6, tonumber(res.headers["ratelimit-limit"]))
        assert.are.same(0, tonumber(res.headers["ratelimit-remaining"]))

        local retry = tonumber(res.headers["retry-after"])
        assert.equal(true, retry <= 60 and retry > 0)

        local reset = tonumber(res.headers["ratelimit-reset"])
        assert.equal(true, reset <= 60 and reset > 0)

        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded" }, json)
      end)
    end)
  end
end
