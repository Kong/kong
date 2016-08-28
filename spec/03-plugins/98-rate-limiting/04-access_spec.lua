local helpers = require "spec.helpers"
local timestamp = require "kong.tools.timestamp"

local REDIS_HOST = "127.0.0.1"
local REDIS_PORT = 6379
local REDIS_PASSWORD = ""

local SLEEP_TIME = 1

local function wait(second_offset)
  -- If the minute elapses in the middle of the test, then the test will
  -- fail. So we give it this test 30 seconds to execute, and if the second
  -- of the current minute is > 30, then we wait till the new minute kicks in
  local current_second = timestamp.get_timetable().sec
  if current_second > (second_offset or 0) then
    os.execute("sleep "..tostring(60 - current_second))
  end
end

wait() -- Wait before starting

local function flush_redis()
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(2000)
  local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
  if not ok then
    error("failed to connect to Redis: ", err)
  end

  if REDIS_PASSWORD and REDIS_PASSWORD ~= "" then
    local ok, err = red:auth(REDIS_PASSWORD)
    if not ok then
      error("failed to connect to Redis: ", err)
    end
  end

  red:flushall()
  red:close()
end

for i, policy in ipairs({"local", "cluster", "redis"}) do
  describe("#ci Plugin: rate-limiting (access) with policy: "..policy, function()
    setup(function()
      helpers.kill_all()
      flush_redis()
      helpers.dao:drop_schema()
      assert(helpers.dao:run_migrations())
      assert(helpers.start_kong())

      local consumer1 = assert(helpers.dao.consumers:insert {
        custom_id = "provider_123"
      })
      assert(helpers.dao.keyauth_credentials:insert {
        key = "apikey122",
        consumer_id = consumer1.id
      })

      local consumer2 = assert(helpers.dao.consumers:insert {
        custom_id = "provider_124"
      })
      assert(helpers.dao.keyauth_credentials:insert {
        key = "apikey123",
        consumer_id = consumer2.id
      })
      assert(helpers.dao.keyauth_credentials:insert {
        key = "apikey333",
        consumer_id = consumer2.id
      })

      local api1 = assert(helpers.dao.apis:insert {
        request_host = "test1.com",
        upstream_url = "http://mockbin.com"
      })
      assert(helpers.dao.plugins:insert {
        name = "rate-limiting",
        api_id = api1.id,
        config = {
          policy = policy,
          minute = 6,
          fault_tolerant = false,
          redis_host = REDIS_HOST,
          redis_port = REDIS_PORT,
          redis_password = REDIS_PASSWORD
        }
      })

      local api2 = assert(helpers.dao.apis:insert {
        request_host = "test2.com",
        upstream_url = "http://mockbin.com"
      })
      assert(helpers.dao.plugins:insert {
        name = "rate-limiting",
        api_id = api2.id,
        config = {
          minute = 3,
          hour = 5,
          fault_tolerant = false,
          policy = policy,
          redis_host = REDIS_HOST,
          redis_port = REDIS_PORT,
          redis_password = REDIS_PASSWORD
        }
      })

      local api3 = assert(helpers.dao.apis:insert {
        request_host = "test3.com",
        upstream_url = "http://mockbin.com"
      })
      assert(helpers.dao.plugins:insert {
        name = "key-auth",
        api_id = api3.id
      })
      assert(helpers.dao.plugins:insert {
        name = "rate-limiting",
        api_id = api3.id,
        config = {
          minute = 6,
          limit_by = "credential",
          fault_tolerant = false,
          policy = policy,
          redis_host = REDIS_HOST,
          redis_port = REDIS_PORT,
          redis_password = REDIS_PASSWORD
        }
      })
      assert(helpers.dao.plugins:insert {
        name = "rate-limiting",
        api_id = api3.id,
        consumer_id = consumer1.id,
        config = {
          minute = 8,
          fault_tolerant = false,
          policy = policy,
          redis_host = REDIS_HOST,
          redis_port = REDIS_PORT,
          redis_password = REDIS_PASSWORD
        }
      })

      local api4 = assert(helpers.dao.apis:insert {
        request_host = "test4.com",
        upstream_url = "http://mockbin.com"
      })
      assert(helpers.dao.plugins:insert {
        name = "key-auth",
        api_id = api4.id
      })
      assert(helpers.dao.plugins:insert {
        name = "rate-limiting",
        api_id = api4.id,
        consumer_id = consumer1.id,
        config = {
          minute = 6,
          fault_tolerant = true,
          policy = policy,
          redis_host = REDIS_HOST,
          redis_port = REDIS_PORT,
          redis_password = REDIS_PASSWORD
        }
      })
    end)
    teardown(function()
      helpers.stop_kong()
    end)

    local client, admin_client
    before_each(function()
      wait(45)
      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)
    after_each(function()
      if client then client:close() end
      if admin_client then admin_client:close() end
    end)

    describe("Without authentication (IP address)", function()
      it("blocks if exceeding limit", function()
        for i = 1, 6 do
          local res = assert(client:send {
            method = "GET",
            path = "/status/200/",
            headers = {
              ["Host"] = "test1.com"
            }
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
        end

        -- Additonal request, while limit is 6/minute
        local res = assert(client:send {
          method = "GET",
          path = "/status/200/",
          headers = {
            ["Host"] = "test1.com"
          }
        })
        local body = assert.res_status(429, res)
        assert.are.equal([[{"message":"API rate limit exceeded"}]], body)
      end)

      it("handles multiple limits", function()
        local limits = {
          minute = 3,
          hour = 5
        }

        for i = 1, 3 do
          local res = assert(client:send {
            method = "GET",
            path = "/status/200/",
            headers = {
              ["Host"] = "test2.com"
            }
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.res_status(200, res)
          assert.are.same(limits.minute, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(limits.minute - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          assert.are.same(limits.hour, tonumber(res.headers["x-ratelimit-limit-hour"]))
          assert.are.same(limits.hour - i, tonumber(res.headers["x-ratelimit-remaining-hour"]))
        end

        local res = assert(client:send {
          method = "GET",
          path = "/status/200/",
          headers = {
            ["Host"] = "test2.com"
          }
        })
        local body = assert.res_status(429, res)
        assert.are.equal([[{"message":"API rate limit exceeded"}]], body)
        assert.are.equal(2, tonumber(res.headers["x-ratelimit-remaining-hour"]))
        assert.are.equal(0, tonumber(res.headers["x-ratelimit-remaining-minute"]))
      end)
    end)
    describe("With authentication", function()
      describe("API-specific plugin", function()
        it("blocks if exceeding limit", function()
          for i = 1, 6 do
            local res = assert(client:send {
              method = "GET",
              path = "/status/200/?apikey=apikey123",
              headers = {
                ["Host"] = "test3.com"
              }
            })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          end

          -- Third query, while limit is 2/minute
          local res = assert(client:send {
            method = "GET",
            path = "/status/200/?apikey=apikey123",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          local body = assert.res_status(429, res)
          assert.are.equal([[{"message":"API rate limit exceeded"}]], body)

          -- Using a different key of the same consumer works
          local res = assert(client:send {
            method = "GET",
            path = "/status/200/?apikey=apikey333",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          assert.res_status(200, res)
        end)
      end)
      describe("Plugin customized for specific consumer", function()
        it("blocks if exceeding limit", function()
          for i = 1, 8 do
            local res = assert(client:send {
              method = "GET",
              path = "/status/200/?apikey=apikey122",
              headers = {
                ["Host"] = "test3.com"
              }
            })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(8, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(8 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          end

          local res = assert(client:send {
            method = "GET",
            path = "/status/200/?apikey=apikey122",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          local body = assert.res_status(429, res)
          assert.are.equal([[{"message":"API rate limit exceeded"}]], body)
        end)
        it("blocks if the only rate-limiting plugin existing is per consumer and not per API", function()
          for i = 1, 6 do
            local res = assert(client:send {
              method = "GET",
              path = "/status/200/?apikey=apikey122",
              headers = {
                ["Host"] = "test4.com"
              }
            })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-minute"]))
          end

          local res = assert(client:send {
            method = "GET",
            path = "/status/200/?apikey=apikey122",
            headers = {
              ["Host"] = "test4.com"
            }
          })
          local body = assert.res_status(429, res)
          assert.are.equal([[{"message":"API rate limit exceeded"}]], body)
        end)
      end)
    end)

    if policy == "cluster" then
      describe("Fault tolerancy", function()

        before_each(function()
          helpers.kill_all()
          helpers.dao:drop_schema()
          assert(helpers.dao:run_migrations())

          local api1 = assert(helpers.dao.apis:insert {
            request_host = "failtest1.com",
            upstream_url = "http://mockbin.com"
          })
          assert(helpers.dao.plugins:insert {
            name = "rate-limiting",
            api_id = api1.id,
            config = { minute = 6, fault_tolerant = false }
          })

          local api2 = assert(helpers.dao.apis:insert {
            request_host = "failtest2.com",
            upstream_url = "http://mockbin.com"
          })
          assert(helpers.dao.plugins:insert {
            name = "rate-limiting",
            api_id = api2.id,
            config = { minute = 6, fault_tolerant = true }
          })

          assert(helpers.start_kong())
        end)

        teardown(function()
          helpers.kill_all()
          helpers.dao:drop_schema()
          assert(helpers.dao:run_migrations())
        end)

        it("does not work if an error occurs", function()
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/status/200/",
            headers = {
              ["Host"] = "failtest1.com"
            }
          })
          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))

          -- Simulate an error on the database
          local err = helpers.dao.ratelimiting_metrics:drop_table(helpers.dao.ratelimiting_metrics.table)
          assert.falsy(err)

          -- Make another request
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/status/200/",
            headers = {
              ["Host"] = "failtest1.com"
            }
          })
          local body = assert.res_status(500, res)
          assert.are.equal([[{"message":"An unexpected error occurred"}]], body)
        end)
        it("keeps working if an error occurs", function()
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/status/200/",
            headers = {
              ["Host"] = "failtest2.com"
            }
          })
          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
          assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))

          -- Simulate an error on the database
          local err = helpers.dao.ratelimiting_metrics:drop_table(helpers.dao.ratelimiting_metrics.table)
          assert.falsy(err)

          -- Make another request
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/status/200/",
            headers = {
              ["Host"] = "failtest2.com"
            }
          })
          assert.res_status(200, res)
          assert.falsy(res.headers["x-ratelimit-limit-minute"])
          assert.falsy(res.headers["x-ratelimit-remaining-minute"])
        end)
      end)
    end

    describe("Expirations", function()
      local api
      setup(function()
        helpers.stop_kong()
        helpers.dao:drop_schema()
        assert(helpers.dao:run_migrations())
        assert(helpers.start_kong())

        api = assert(helpers.dao.apis:insert {
          request_host = "expire1.com",
          upstream_url = "http://mockbin.com"
        })
        assert(helpers.dao.plugins:insert {
          name = "rate-limiting",
          api_id = api.id,
          config = {
            minute = 6,
            policy = policy,
            redis_host = REDIS_HOST,
            redis_port = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            fault_tolerant = false
          }
        })
      end)

      it("expires a counter", function()
        local periods = timestamp.get_timestamps()

        local res = assert(client:send {
          method = "GET",
          path = "/status/200/",
          headers = {
            ["Host"] = "expire1.com"
          }
        })

        ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

        assert.res_status(200, res)
        assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
        assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))

        if policy == "local" then
          local res = assert(admin_client:send {
            method = "GET",
            path = "/cache/"..string.format("ratelimit:%s:%s:%s:%s", api.id, "127.0.0.1", periods.minute, "minute")
          })
          local body = assert.res_status(200, res)
          assert.equal([[{"message":1}]], body)
        end

        ngx.sleep(61) -- Wait for counter to expire

        local res = assert(client:send {
          method = "GET",
          path = "/status/200/",
          headers = {
            ["Host"] = "expire1.com"
          }
        })

        ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

        assert.res_status(200, res)
        assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-minute"]))
        assert.are.same(5, tonumber(res.headers["x-ratelimit-remaining-minute"]))

        if policy == "local" then
          local res = assert(admin_client:send {
            method = "GET",
            path = "/cache/"..string.format("ratelimit:%s:%s:%s:%s", api.id, "127.0.0.1", periods.minute, "minute")
          })
          assert.res_status(404, res)
        end
      end)
    end)
  end)
end
