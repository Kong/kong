local helpers = require "spec.helpers"
local timestamp = require "kong.tools.timestamp"

local function wait()
  -- If the minute elapses in the middle of the test, then the test will
  -- fail. So we give it this test 30 seconds to execute, and if the second
  -- of the current minute is > 30, then we wait till the new minute kicks in
  local current_second = timestamp.get_timetable().sec
  if current_second > 1 then
    os.execute("sleep "..tostring(60 - current_second))
  end
end

describe("Plugin: rate-limiting", function()
  local client

  local function prepare()
    helpers.kill_all()
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

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "test3.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api1.id
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api1.id,
      config = { minute = 6 }
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api1.id,
      consumer_id = consumer1.id,
      config = { minute = 8 }
    })

    local api2 = assert(helpers.dao.apis:insert {
      request_host = "test4.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api2.id,
      config = { minute = 6 }
    })

    local api3 = assert(helpers.dao.apis:insert {
      request_host = "test5.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api3.id,
      config = { minute = 3, hour = 5 }
    })

    local api4 = assert(helpers.dao.apis:insert {
      request_host = "test6.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api4.id,
      config = { minute = 33 }
    })

    local api5 = assert(helpers.dao.apis:insert {
      request_host = "test7.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api5.id,
      config = { minute = 6, async = true }
    })

    local api6 = assert(helpers.dao.apis:insert {
      request_host = "test8.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api6.id,
      config = { minute = 6, continue_on_error = false }
    })

    local api7 = assert(helpers.dao.apis:insert {
      request_host = "test9.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api7.id,
      config = { minute = 6, continue_on_error = true }
    })

    local api8 = assert(helpers.dao.apis:insert {
      request_host = "test10.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api8.id
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api8.id,
      consumer_id = consumer1.id,
      config = { minute = 6, continue_on_error = true }
    })
  end

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)

  setup(function()
    prepare()
    wait()
  end)
  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
    --helpers.clean_prefix()
  end)

  describe("Without authentication (IP address)", function()
    it("should get blocked if exceeding limit", function()
      -- Default rate-limiting plugin for this API says 6/minute
      local limit = 6

      for i = 1, limit do
        --client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
        local res = assert(client:send {
          method = "GET",
          path = "/status/200/",
          headers = {
            ["Host"] = "test4.com"
          }
        })
        assert.res_status(200, res)
        assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-minute"])
        assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-minute"])
      end

      -- Additonal request, while limit is 6/minute
      local res = assert(client:send {
        method = "GET",
        path = "/status/200/",
        headers = {
          ["Host"] = "test4.com"
        }
      })
      local body = assert.res_status(429, res)
      assert.are.equal([[{"message":"API rate limit exceeded"}]], body)
    end)

    it("should handle multiple limits", function()
      local limits = {
        minute = 3,
        hour = 5
      }

      for i = 1, 3 do
        local res = assert(client:send {
          method = "GET",
          path = "/status/200/",
          headers = {
            ["Host"] = "test5.com"
          }
        })
        assert.res_status(200, res)

        assert.are.same(tostring(limits.minute), res.headers["x-ratelimit-limit-minute"])
        assert.are.same(tostring(limits.minute - i), res.headers["x-ratelimit-remaining-minute"])
        assert.are.same(tostring(limits.hour), res.headers["x-ratelimit-limit-hour"])
        assert.are.same(tostring(limits.hour - i), res.headers["x-ratelimit-remaining-hour"])
      end

      local res = assert(client:send {
        method = "GET",
        path = "/status/200/",
        headers = {
          ["Host"] = "test5.com"
        }
      })
      local body = assert.res_status(429, res)
      assert.are.equal([[{"message":"API rate limit exceeded"}]], body)
      assert.are.equal("2", res.headers["x-ratelimit-remaining-hour"])
      assert.are.equal("0", res.headers["x-ratelimit-remaining-minute"])
    end)
  end)

  describe("With authentication", function()
    describe("Default plugin", function()
      it("should get blocked if exceeding limit", function()
        -- Default rate-limiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local res = assert(client:send {
            method = "GET",
            path = "/status/200/?apikey=apikey123",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          assert.res_status(200, res)
          assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-minute"])
          assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-minute"])
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
      end)
    end)

    describe("Plugin customized for specific consumer", function()
      it("should get blocked if exceeding limit", function()
        -- This plugin says this consumer can make 4 requests/minute, not 6 like the default
        local limit = 8

        for i = 1, limit do
          local res = assert(client:send {
            method = "GET",
            path = "/status/200/?apikey=apikey122",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          assert.res_status(200, res)
          assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-minute"])
          assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-minute"])
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
      it("should get blocked if the only rate-limiting plugin existing is per consumer and not per API", function()
        -- This plugin says this consumer can make 4 requests/minute, not 6 like the default
        local limit = 6

        for i = 1, limit do
          local res = assert(client:send {
            method = "GET",
            path = "/status/200/?apikey=apikey122",
            headers = {
              ["Host"] = "test10.com"
            }
          })
          assert.res_status(200, res)
          assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-minute"])
          assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-minute"])
        end

        local res = assert(client:send {
          method = "GET",
          path = "/status/200/?apikey=apikey122",
          headers = {
            ["Host"] = "test10.com"
          }
        })
        local body = assert.res_status(429, res)
        assert.are.equal([[{"message":"API rate limit exceeded"}]], body)
      end)
    end)
  end)

  describe("Async increment", function()
    it("should increment asynchronously", function()
      -- Default rate-limiting plugin for this API says 6/minute
      local limit = 6

      for i = 1, limit do
        local res = assert(client:send {
          method = "GET",
          path = "/status/200/",
          headers = {
            ["Host"] = "test7.com"
          }
        })
        assert.res_status(200, res)
        assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-minute"])
        assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-minute"])
        ngx.sleep(3) -- Wait for timers to increment
      end

      local res = assert(client:send {
        method = "GET",
        path = "/status/200/",
        headers = {
          ["Host"] = "test7.com"
        }
      })
      local body = assert.res_status(429, res)
      assert.are.equal([[{"message":"API rate limit exceeded"}]], body)
    end)
  end)

  describe("Continue on error", function()
    after_each(function()
      prepare()
    end)
    it("should not continue if an error occurs", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200/",
        headers = {
          ["Host"] = "test8.com"
        }
      })
      assert.res_status(200, res)
      assert.are.same(tostring(6), res.headers["x-ratelimit-limit-minute"])
      assert.are.same(tostring(5), res.headers["x-ratelimit-remaining-minute"])

      -- Simulate an error on the database
      local err = helpers.dao.ratelimiting_metrics:drop_table(helpers.dao.ratelimiting_metrics.table)
      assert.falsy(err)

      -- Make another request
      local res = assert(client:send {
        method = "GET",
        path = "/status/200/",
        headers = {
          ["Host"] = "test8.com"
        }
      })
      local body = assert.res_status(500, res)
      assert.are.equal([[{"message":"An unexpected error occurred"}]], body)
    end)
    it("should continue if an error occurs", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200/",
        headers = {
          ["Host"] = "test9.com"
        }
      })
      assert.res_status(200, res)
      assert.are.same(tostring(6), res.headers["x-ratelimit-limit-minute"])
      assert.are.same(tostring(5), res.headers["x-ratelimit-remaining-minute"])

      -- Simulate an error on the database
      local err = helpers.dao.ratelimiting_metrics:drop_table(helpers.dao.ratelimiting_metrics.table)
      assert.falsy(err)

      -- Make another request
      local res = assert(client:send {
        method = "GET",
        path = "/status/200/",
        headers = {
          ["Host"] = "test9.com"
        }
      })
      assert.res_status(200, res)
      assert.falsy(res.headers["x-ratelimit-limit-minute"])
      assert.falsy(res.headers["x-ratelimit-remaining-minute"])
    end)
  end)

end)
