local cjson = require "cjson"
local helpers = require "spec.helpers"
local timestamp = require "kong.tools.timestamp"

local SLEEP_VALUE = "0.5"

local function wait()
  -- If the minute elapses in the middle of the test, then the test will
  -- fail. So we give it this test 30 seconds to execute, and if the second
  -- of the current minute is > 30, then we wait till the new minute kicks in
  local current_second = timestamp.get_timetable().sec
  if current_second > 20 then
    os.execute("sleep "..tostring(60 - current_second))
  end
end

describe("Plugin: response-ratelimiting (access)", function()
  local client

  local function prepare()
    helpers.dao:drop_schema()
    assert(helpers.dao:run_migrations())

    local consumer = assert(helpers.dao.consumers:insert {custom_id = "provider_123"})
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey123",
      consumer_id = consumer.id
    })

    local consumer2 = assert(helpers.dao.consumers:insert {custom_id = "provider_124"})
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey124",
      consumer_id = consumer2.id
    })

    local consumer3 = assert(helpers.dao.consumers:insert {custom_id = "provider_125"})
    assert(helpers.dao.keyauth_credentials:insert {
      key = "apikey125",
      consumer_id = consumer3.id
    })

    -- test1.com
    local api = assert(helpers.dao.apis:insert {
      request_host = "test1.com",
      upstream_url = "http://httpbin.org"
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      config = {limits = {video = {minute = 6}}}
    })

    -- test2.com
    api = assert(helpers.dao.apis:insert {
      request_host = "test2.com",
      upstream_url = "http://httpbin.org"
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      config = {limits = {video = {minute = 6, hour = 10}, image = {minute = 4}}}
    })

    -- test3.com
    api = assert(helpers.dao.apis:insert {
      request_host = "test3.com",
      upstream_url = "http://httpbin.org"
    })
    assert(helpers.dao.plugins:insert {
      name = "key-auth",
      api_id = api.id
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      config = {limits = {video = {minute = 6}}}
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      consumer_id = consumer.id,
      config = {limits = {video = {minute = 2}}}
    })

    -- test4.com
    api = assert(helpers.dao.apis:insert {
      request_host = "test4.com",
      upstream_url = "http://httpbin.org"
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      config = {continue_on_error = false, limits = {video = {minute = 6}}}
    })

    -- test5.com
    api = assert(helpers.dao.apis:insert {
      request_host = "test5.com",
      upstream_url = "http://httpbin.org"
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      config = {continue_on_error = true, limits = {video = {minute = 6}}}
    })

    -- test6.com
    api = assert(helpers.dao.apis:insert {
      request_host = "test6.com",
      upstream_url = "http://httpbin.org"
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      config = {continue_on_error = true, limits = {video = {minute = 2}}}
    })

    -- test7.com
    api = assert(helpers.dao.apis:insert {
      request_host = "test7.com",
      upstream_url = "http://httpbin.org"
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      config = {
        continue_on_error = false,
        block_on_first_violation = true,
        limits = {
          video = {
            minute = 6,
            hour = 10
          },
          image = {
            minute = 4
          }
        }
      }
    })

    -- test8.com
    api = assert(helpers.dao.apis:insert {
      request_host = "test8.com",
      upstream_url = "http://httpbin.org"
    })
    assert(helpers.dao.plugins:insert {
      name = "response-ratelimiting",
      api_id = api.id,
      config = {limits = {video = {minute = 6, hour = 10}, image = {minute = 4}}}
    })

    helpers.prepare_prefix()
    assert(helpers.start_kong())
  end

  setup(function()
    prepare()
    wait()
  end)
  teardown(function()
    assert(helpers.stop_kong())
    helpers.clean_prefix()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)
  after_each(function()
    if client then client:close() end
  end)

  describe("Without authentication (IP address)", function()
    it("should get blocked if exceeding limit", function()
      -- Default ratelimiting plugin for this API says 6/minute
      local limit = 6

      for i = 1, limit do
        local res = assert(client:send {
          method = "GET",
          path = "/response-headers?x-kong-limit=video=1, test=5",
          headers = {
            ["Host"] = "test1.com"
          }
        })
        assert.res_status(200, res)
        assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-video-minute"])
        assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-video-minute"])

        ngx.sleep(SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
      end

      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=1",
        headers = {
          ["Host"] = "test1.com"
        }
      })
      local body = assert.res_status(429, res)
      assert.are.equal([[]], body)
    end)

    it("should handle multiple limits", function()
      for i = 1, 3 do
        local res = assert(client:send {
          method = "GET",
          path = "/response-headers?x-kong-limit=video=2, image=1",
          headers = {
            ["Host"] = "test2.com"
          }
        })
        assert.res_status(200, res)
        assert.are.same(tostring(6), res.headers["x-ratelimit-limit-video-minute"])
        assert.are.same(tostring(6 - (i * 2)), res.headers["x-ratelimit-remaining-video-minute"])
        assert.are.same(tostring(10), res.headers["x-ratelimit-limit-video-hour"])
        assert.are.same(tostring(10 - (i * 2)), res.headers["x-ratelimit-remaining-video-hour"])
        assert.are.same(tostring(4), res.headers["x-ratelimit-limit-image-minute"])
        assert.are.same(tostring(4 - i), res.headers["x-ratelimit-remaining-image-minute"])

        ngx.sleep(SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
      end

      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=2, image=1",
        headers = {
          ["Host"] = "test2.com"
        }
      })
      local body = assert.res_status(429, res)
      assert.are.equal([[]], body)
      assert.are.equal("0", res.headers["x-ratelimit-remaining-video-minute"])
      assert.are.equal("4", res.headers["x-ratelimit-remaining-video-hour"])
      assert.are.equal("1", res.headers["x-ratelimit-remaining-image-minute"])
    end)
  end)

  describe("With authentication", function()
    describe("Default plugin", function()
      it("should get blocked if exceeding limit and a per consumer setting", function()
         -- Default ratelimiting plugin for this API says 6/minute
        local limit = 2

        for i = 1, limit do
          local res = assert(client:send {
            method = "GET",
            path = "/response-headers?apikey=apikey123&x-kong-limit=video=1",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          assert.res_status(200, res)
          assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-video-minute"])
          assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-video-minute"])
          ngx.sleep(SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
        end

        -- Third query, while limit is 2/minute
        local res = assert(client:send {
          method = "GET",
          path = "/response-headers?apikey=apikey123&x-kong-limit=video=1",
          headers = {
            ["Host"] = "test3.com"
          }
        })
        local body = assert.res_status(429, res)
        assert.are.equal([[]], body)
        assert.are.equal("0", res.headers["x-ratelimit-remaining-video-minute"])
        assert.are.equal("2", res.headers["x-ratelimit-limit-video-minute"])
      end)

      it("should get blocked if exceeding limit and a per consumer setting", function()
        -- Default ratelimiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local res = assert(client:send {
            method = "GET",
            path = "/response-headers?apikey=apikey124&x-kong-limit=video=1",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          assert.res_status(200, res)
          assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-video-minute"])
          assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-video-minute"])
          ngx.sleep(SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
        end

        local res = assert(client:send {
          method = "GET",
          path = "/response-headers?apikey=apikey124",
          headers = {
            ["Host"] = "test3.com"
          }
        })
        assert.res_status(200, res)
        assert.are.equal("0", res.headers["x-ratelimit-remaining-video-minute"])
        assert.are.equal("6", res.headers["x-ratelimit-limit-video-minute"])
      end)

      it("should get blocked if exceeding limit", function()
        -- Default ratelimiting plugin for this API says 6/minute
        local limit = 6

        for i = 1, limit do
          local res = assert(client:send {
            method = "GET",
            path = "/response-headers?apikey=apikey125&x-kong-limit=video=1",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          assert.res_status(200, res)
          assert.are.same(tostring(limit), res.headers["x-ratelimit-limit-video-minute"])
          assert.are.same(tostring(limit - i), res.headers["x-ratelimit-remaining-video-minute"])
          ngx.sleep(SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time
        end

        -- Third query, while limit is 2/minute
        local res = assert(client:send {
          method = "GET",
          path = "/response-headers?apikey=apikey125&x-kong-limit=video=1",
          headers = {
            ["Host"] = "test3.com"
          }
        })
        local body = assert.res_status(429, res)
        assert.are.equal([[]], body)
        assert.are.equal("0", res.headers["x-ratelimit-remaining-video-minute"])
        assert.are.equal("6", res.headers["x-ratelimit-limit-video-minute"])
      end)
    end)
  end)

  describe("Upstream usage headers", function()
    it("should append the headers with multiple limits", function()
      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          ["Host"] = "test8.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.are.equal("4", body.headers["X-Ratelimit-Remaining-Image"])
      assert.are.equal("6", body.headers["X-Ratelimit-Remaining-Video"])

      -- Actually consume the limits
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=2, image=1",
        headers = {
          ["Host"] = "test8.com"
        }
      })
      assert.res_status(200, res)
      ngx.sleep(SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time

      local res = assert(client:send {
        method = "GET",
        path = "/get",
        headers = {
          ["Host"] = "test8.com"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.are.equal("3", body.headers["X-Ratelimit-Remaining-Image"])
      assert.are.equal("4", body.headers["X-Ratelimit-Remaining-Video"])
    end)
  end)

  it("should block on first violation", function()
    local res = assert(client:send {
      method = "GET",
      path = "/response-headers?x-kong-limit=video=2, image=4",
      headers = {
        ["Host"] = "test7.com"
      }
    })
    assert.res_status(200, res)
    ngx.sleep(SLEEP_VALUE) -- The increment happens in log_by_lua, give it some time

    local res = assert(client:send {
      method = "GET",
      path = "/response-headers?x-kong-limit=video=2",
      headers = {
        ["Host"] = "test7.com"
      }
    })
    local body = assert.res_status(429, res)
    assert.are.equal([[{"message":"API rate limit exceeded for 'image'"}]], body)
  end)

  describe("Continue on error", function()
    after_each(function()
      prepare()
    end)

    it("should not continue if an error occurs", function()
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=1",
        headers = {
          ["Host"] = "test4.com"
        }
      })
      assert.res_status(200, res)
      assert.are.same("6", res.headers["x-ratelimit-limit-video-minute"])
      assert.are.same("5", res.headers["x-ratelimit-remaining-video-minute"])

      -- Simulate an error on the database
      local err = helpers.dao.response_ratelimiting_metrics:drop_table(helpers.dao.response_ratelimiting_metrics.table)
      assert.falsy(err)

      -- Make another request
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=1",
        headers = {
          ["Host"] = "test4.com"
        }
      })
      local body = assert.res_status(500, res)
      assert.are.equal([[{"message":"An unexpected error occurred"}]], body)
    end)

    it("should continue if an error occurs", function()
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=1",
        headers = {
          ["Host"] = "test5.com"
        }
      })
      assert.res_status(200, res)
      assert.are.same("6", res.headers["x-ratelimit-limit-video-minute"])
      assert.are.same("5", res.headers["x-ratelimit-remaining-video-minute"])

      -- Simulate an error on the database
      local err = helpers.dao.response_ratelimiting_metrics:drop_table(helpers.dao.response_ratelimiting_metrics.table)
      assert.falsy(err)

      -- Make another request
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=1",
        headers = {
          ["Host"] = "test5.com"
        }
      })
      assert.res_status(200, res)
      assert.is_nil(res.headers["x-ratelimit-limit-video-minute"])
      assert.is_nil(res.headers["x-ratelimit-remaining-video-minute"])
    end)
  end)
end)
