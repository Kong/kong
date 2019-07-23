local helpers = require "spec.helpers"
local cjson = require "cjson"
local redis = require "kong.enterprise_edition.redis"

local REDIS_HOST = "127.0.0.1"
local REDIS_PORT = 6379
local REDIS_DATABASE = 1
local REDIS_PASSWORD = nil

for i, policy in ipairs({"cluster", "redis"}) do
  local MOCK_RATE = 3

  local s = "rate-limiting-advanced (access) with policy: " .. policy
  if policy == "redis" then
    s = "#flaky " .. s
  end

  describe(s, function()
    local bp, consumer1, consumer2

    setup(function()
      helpers.kill_all()
      redis.flush_redis(REDIS_HOST, REDIS_PORT, REDIS_DATABASE, REDIS_PASSWORD)

      bp = helpers.get_db_utils(nil, nil, {"rate-limiting-advanced"})

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
        hosts = { "test1.com" },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route1.id },
        config = {
          strategy = policy,
          window_size = { MOCK_RATE },
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      local route2 = assert(bp.routes:insert {
        name = "route-2",
        hosts = { "test2.com" },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route2.id },
        config = {
          strategy = policy,
          window_size = { 5, 10 },
          limit = { 3, 5 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      local route3 = assert(bp.routes:insert {
        name = "route-3",
        hosts = { "test3.com" },
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route3.id },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route3.id },
        config = {
          identifier = "credential",
          strategy = policy,
          window_size = { MOCK_RATE },
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      local route4 = assert(bp.routes:insert {
        name = "route-4",
        hosts = { "test4.com" },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route4.id },
        config = {
          strategy = policy,
          window_size = { MOCK_RATE },
          limit = { 3 },
          sync_rate = 10,
          namespace = "foo",
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      local route5 = assert(bp.routes:insert {
        name = "route-5",
        hosts = { "test5.com" },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route5.id },
        config = {
          strategy = policy,
          window_size = { MOCK_RATE },
          limit = { 3 },
          sync_rate = 10,
          namespace = "foo",
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      local route6 = assert(bp.routes:insert {
        name = "route-6",
        hosts = { "test6.com" },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route6.id },
        config = {
          strategy = policy,
          window_size = { MOCK_RATE },
          window_type = "fixed",
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      local route7 = assert(bp.routes:insert {
        name = "route-7",
        hosts = { "test7.com" },
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route7.id },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route7.id },
        config = {
          strategy = policy,
          window_size = { MOCK_RATE },
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      local route8 = assert(bp.routes:insert {
        name = "route-8",
        hosts = { "test8.com" },
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route8.id },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route8.id },
        config = {
          identifier = "ip",
          strategy = policy,
          window_size = { MOCK_RATE },
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      local route9 = assert(bp.routes:insert {
        name = "route-9",
        hosts = { "test9.com" },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route9.id },
        config = {
          strategy = policy,
          window_size = { MOCK_RATE },
          window_type = "fixed",
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          },
          hide_client_headers = true
        }
      })

      local route10 = assert(bp.routes:insert {
        name = "route-10",
        hosts = { "test10.com" },
      })

      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route10.id },
        config = {
          strategy = policy,
          identifier = "service",
          window_size = { MOCK_RATE },
          window_type = "fixed",
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          },
        }
      })

      local route11 = assert(bp.routes:insert {
        name = "route-11",
        hosts = { "test11.com" },
      })

      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route11.id },
        config = {
          strategy = policy,
          identifier = "service",
          window_size = { MOCK_RATE },
          window_type = "fixed",
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          },
        }
      })

      local route12 = assert(bp.routes:insert {
        name = "route-12",
        hosts = { "test12.com" },
      })
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route12.id },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting-advanced",
        route = { id = route12.id },
        config = {
          identifier = "header",
          header_name = "x-email-address",
          strategy = policy,
          window_size = { MOCK_RATE },
          limit = { 6 },
          sync_rate = 10,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            password = REDIS_PASSWORD,
          }
        }
      })

      assert(helpers.start_kong{
        plugins = "rate-limiting-advanced,key-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      })
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    local client, admin_client
    before_each(function()
      client = helpers.proxy_client()
      admin_client = helpers.admin_client()

      local rate = MOCK_RATE
      ngx.sleep(rate - (ngx.now() - (math.floor(ngx.now() / rate) * rate)))
    end)

    after_each(function()
      if client then client:close() end
      if admin_client then admin_client:close() end
    end)

    describe("Without authentication (IP address)", function()
      it("blocks if exceeding limit", function()
        for i = 1, 6 do
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test1.com"
            }
          })

          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
          assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
        end

        -- Additonal request, while limit is 6/window
        local res = assert(helpers.proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            ["Host"] = "test1.com"
          }
        })
        local body = assert.res_status(429, res)
        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded" }, json)

        -- wait a bit longer than our window size
        ngx.sleep(MOCK_RATE + 1)

        -- Additonal request, sliding window is 0 < rate <= limit
        res = assert(helpers.proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            ["Host"] = "test1.com"
          }
        })
        assert.res_status(200, res)
        local rate = tonumber(res.headers["x-ratelimit-remaining-3"])
        assert.is_true(0 < rate and rate <= 6)
      end)

      it("resets the counter", function()
        -- clear our windows entirely
        ngx.sleep(MOCK_RATE * 2)

        -- Additonal request, sliding window is reset and one less than limit
        local res = assert(helpers.proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            ["Host"] = "test1.com"
          }
        })
        assert.res_status(200, res)
        assert.same(5, tonumber(res.headers["x-ratelimit-remaining-3"]))
      end)

      it("shares limit data in the same namespace", function()
        -- decrement the counters in route4
        for i = 1, 3 do
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test4.com"
            }
          })

          assert.res_status(200, res)
          assert.are.same(3, tonumber(res.headers["x-ratelimit-limit-3"]))
          assert.are.same(3 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
        end

        -- access route5, which shares the same namespace
        local res = assert(helpers.proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            ["Host"] = "test5.com"
          }
        })
        local body = assert.res_status(429, res)
        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded" }, json)
      end)

      local name = "handles multiple limits"
      if policy == "redis" then
        name = "#flaky " .. name
      end
      it(name, function()
        local limits = {
          ["5"] = 3,
          ["10"] = 5,
        }

        for i = 1, 3 do
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test2.com"
            }
          })

          assert.res_status(200, res)
          assert.same(limits["5"], tonumber(res.headers["x-ratelimit-limit-5"]))
          assert.same(limits["5"] - i, tonumber(res.headers["x-ratelimit-remaining-5"]))
          assert.same(limits["10"], tonumber(res.headers["x-ratelimit-limit-10"]))
          assert.same(limits["10"] - i, tonumber(res.headers["x-ratelimit-remaining-10"]))
        end

        -- once we have reached a limit, ensure we do not dip below 0,
        -- and do not alter other limits
        for i = 1, 5 do
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test2.com"
            }
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)
          assert.same(2, tonumber(res.headers["x-ratelimit-remaining-10"]))
          assert.same(0, tonumber(res.headers["x-ratelimit-remaining-5"]))
        end
      end)

      it("implements a fixed window if instructed to do so", function()
        for i = 1, 6 do
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test6.com"
            }
          })

          assert.res_status(200, res)
          assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
          assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
        end

        -- Additonal request, while limit is 6/window
        local res = assert(helpers.proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            ["Host"] = "test6.com"
          }
        })
        local body = assert.res_status(429, res)
        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded" }, json)

        -- wait a bit longer than our window size
        ngx.sleep(MOCK_RATE + 0.1)

        -- Additonal request, window/rate is reset
        res = assert(helpers.proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            ["Host"] = "test6.com"
          }
        })
        assert.res_status(200, res)
        local remaining = tonumber(res.headers["x-ratelimit-remaining-3"])
        assert.same(5, remaining)
      end)

      it("hides headers if hide_client_headers is true", function()
        local res = assert(helpers.proxy_client():send {
          method = "GET",
          path = "/get",
          headers = {
            ["Host"] = "test9.com"
          }
        })

        assert.is_nil(res.headers["x-ratelimit-remaining-3"])
        assert.is_nil(res.headers["x-ratelimit-limit-3"])
      end)
    end)
    describe("With authentication", function()
      describe("Route-specific plugin", function()
        local name = "blocks if exceeding limit"
        if policy == "redis" then
          name = "#flaky " .. name
        end
        it(name, function()
          for i = 1, 6 do
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test3.com"
              }
            })

            assert.res_status(200, res)
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
          end

          -- Third query, while limit is 6/window
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey123",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)

          -- Using a different key of the same consumer works
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey333",
            headers = {
              ["Host"] = "test3.com"
            }
          })
          assert.res_status(200, res)
        end)
      end)
    end)
    describe("With identifier", function()
      describe("not set, use default `consumer`", function()
        it("should not block consumer1 when limit exceed for consumer2", function()
          for i = 1, 6 do
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test7.com"
              }
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.are.same(consumer2.id, json.headers["x-consumer-id"])
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
          end

          -- Additonal request, while limit is 6/window, for
          -- consumer2 should be blocked
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey123",
            headers = {
              ["Host"] = "test7.com"
            }
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)

          -- consumer1 should still be able to make request as
          -- limit is set by consumer not IP
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey122",
            headers = {
              ["Host"] = "test7.com"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.are.same(consumer1.id, json.headers["x-consumer-id"])

          -- wait a bit longer than our window size
          ngx.sleep(MOCK_RATE + 1)
        end)
      end)
      describe("set to `ip`", function()
        it("should block consumer1 when consumer2 breach limit", function()
          for i = 1, 6 do
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test8.com"
              }
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.are.same(consumer2.id, json.headers["x-consumer-id"])
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
          end

          -- Additonal request, while limit is 6/window, for consumer2
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey123",
            headers = {
              ["Host"] = "test8.com"
            }
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)

          -- consumer1 should not be able to make request as
          -- limit is set by IP
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey122",
            headers = {
              ["Host"] = "test8.com"
            }
          })
          assert.res_status(429, res)
        end)
      end)
      describe("set to `#service`", function()
        it("should be global to service, and independent between services", function()
          for i = 1, 6 do
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get",
              headers = {
                ["Host"] = "test10.com"
              }
            })
            assert.res_status(200, res)
          end

          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test10.com"
            }
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)

          -- service11 should still be able to make request as
          -- limit is set by service
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get",
            headers = {
              ["Host"] = "test11.com"
            }
          })
          assert.res_status(200, res)
        end)
      end)
      describe("set to `header` + customers use the same headers", function()
        it("should block consumer1 when consumer2 breach limit", function()
          for i = 1, 6 do
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test12.com",
                ["x-email-address"] = "test1@example.com",
              }
            })

             local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.are.same(consumer2.id, json.headers["x-consumer-id"])
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
          end

           -- Additonal request, while limit is 6/window, for consumer2
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey123",
            headers = {
              ["Host"] = "test12.com",
              ["x-email-address"] = "test1@example.com",
            }
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)

           -- consumer1 should not be able to make request as limit is set by
          -- header and both consumers use the same header values
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey122",
            headers = {
              ["Host"] = "test12.com",
              ["x-email-address"] = "test1@example.com",
            }
          })
          assert.res_status(429, res)
        end)
      end)
      describe("set to `header` + customers use different headers", function()
        it("should not block consumer1 when consumer2 breach limit", function()
          for i = 1, 6 do
            local res = assert(helpers.proxy_client():send {
              method = "GET",
              path = "/get?apikey=apikey123",
              headers = {
                ["Host"] = "test12.com",
                ["x-email-address"] = "test2@example.com"
              }
            })

             local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.are.same(consumer2.id, json.headers["x-consumer-id"])
            assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-3"]))
            assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-3"]))
          end

           -- Additonal request, while limit is 6/window, for consumer2
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey123",
            headers = {
              ["Host"] = "test12.com",
              ["x-email-address"] = "test2@example.com",
            }
          })
          local body = assert.res_status(429, res)
          local json = cjson.decode(body)
          assert.same({ message = "API rate limit exceeded" }, json)

           -- consumer1 should still be able to make request as limit is set by -- header and both consumers use different header values
          local res = assert(helpers.proxy_client():send {
            method = "GET",
            path = "/get?apikey=apikey122",
            headers = {
              ["Host"] = "test12.com",
              ["x-email-address"] = "test3@example.com",
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.are.same(consumer1.id, json.headers["x-consumer-id"])
        end)
      end)
    end)
  end)
end
