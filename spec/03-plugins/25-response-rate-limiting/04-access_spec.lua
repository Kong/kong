local cjson          = require "cjson"
local helpers        = require "spec.helpers"
local timestamp      = require "kong.tools.timestamp"


local REDIS_HOST     = "127.0.0.1"
local REDIS_PORT     = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 1


local SLEEP_TIME = 1


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
  for i, policy in ipairs({"local", "cluster", "redis"}) do
    describe(fmt("#flaky Plugin: response-ratelimiting (access) with policy: %s [#%s]", policy, strategy), function()
      local dao
      local db
      local bp

      setup(function()
        bp, db, dao = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
          "consumers",
          "keyauth_credentials",
        })
        dao.db:truncate_table("response_ratelimiting_metrics")

        flush_redis()

        local consumer1 = bp.consumers:insert {custom_id = "provider_123"}
        bp.keyauth_credentials:insert {
          key         = "apikey123",
          consumer_id = consumer1.id
        }

        local consumer2 = bp.consumers:insert {custom_id = "provider_124"}
        bp.keyauth_credentials:insert {
          key         = "apikey124",
          consumer_id = consumer2.id
        }

        local consumer3 = bp.consumers:insert {custom_id = "provider_125"}
        bp.keyauth_credentials:insert {
          key         = "apikey125",
          consumer_id = consumer3.id
        }

        local service1 = bp.services:insert()

        local route1 = bp.routes:insert {
          hosts      = { "test1.com" },
          protocols  = { "http", "https" },
          service    = service1
        }

        bp.response_ratelimiting_plugins:insert({
          route = { id = route1.id },
          config   = {
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            limits         = { video = { minute = 6 } },
          },
        })

        local service2 = bp.services:insert()

        local route2 = bp.routes:insert {
          hosts      = { "test2.com" },
          protocols  = { "http", "https" },
          service    = service2
        }

        bp.response_ratelimiting_plugins:insert({
          route = { id = route2.id },
          config   = {
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            limits         = { video = { minute = 6, hour = 10 },
                               image = { minute = 4 } },
          },
        })

        local service3 = bp.services:insert()

        local route3 = bp.routes:insert {
          hosts      = { "test3.com" },
          protocols  = { "http", "https" },
          service    = service3
        }

        bp.plugins:insert {
          name     = "key-auth",
          route = { id = route3.id },
        }

        bp.response_ratelimiting_plugins:insert({
          route = { id = route3.id },
          config   = { limits = { video = { minute = 6 } } },
        })

        bp.response_ratelimiting_plugins:insert({
          route = { id = route3.id },
          consumer = { id = consumer1.id },
          config      = {
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            limits         = { video = { minute = 2 } },
          },
        })

        local service4 = bp.services:insert()

        local route4 = bp.routes:insert {
          hosts      = { "test4.com" },
          protocols  = { "http", "https" },
          service    = service4
        }

        bp.response_ratelimiting_plugins:insert({
          route = { id = route4.id },
          config   = {
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            limits         = { video = { minute = 6 }, image = { minute = 4 } },
          }
        })

        local service7 = bp.services:insert()

        local route7 = bp.routes:insert {
          hosts      = { "test7.com" },
          protocols  = { "http", "https" },
          service    = service7
        }

        bp.response_ratelimiting_plugins:insert({
          route = { id = route7.id },
          config   = {
            fault_tolerant           = false,
            policy                   = policy,
            redis_host               = REDIS_HOST,
            redis_port               = REDIS_PORT,
            redis_password           = REDIS_PASSWORD,
            redis_database           = REDIS_DATABASE,
            block_on_first_violation = true,
            limits                   = {
              video = {
                minute = 6,
                hour  = 10,
              },
              image = {
                minute = 4,
              },
            },
          }
        })

        local service8 = bp.services:insert()

        local route8 = bp.routes:insert {
          hosts      = { "test8.com" },
          protocols  = { "http", "https" },
          service    = service8
        }

        bp.response_ratelimiting_plugins:insert({
          route = { id = route8.id },
          config   = {
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            limits         = { video = { minute = 6, hour = 10 },
                               image = { minute = 4 } },
          }
        })

        local service9 = bp.services:insert()

        local route9 = bp.routes:insert {
          hosts      = { "test9.com" },
          protocols  = { "http", "https" },
          service    = service9
        }

        bp.response_ratelimiting_plugins:insert({
          route = { id = route9.id },
          config   = {
            fault_tolerant      = false,
            policy              = policy,
            hide_client_headers = true,
            redis_host          = REDIS_HOST,
            redis_port          = REDIS_PORT,
            redis_password      = REDIS_PASSWORD,
            redis_database      = REDIS_DATABASE,
            limits              = { video = { minute = 6 } },
          }
        })


        local service10 = bp.services:insert()
        bp.routes:insert {
          hosts = { "test-service1.com" },
          service = service10,
        }
        bp.routes:insert {
          hosts = { "test-service2.com" },
          service = service10,
        }

        bp.response_ratelimiting_plugins:insert({
          service = { id = service10.id },
          config = {
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            limits         = { video = { minute = 6 } },
          }
        })

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        wait(45)
      end)

      describe("Without authentication (IP address)", function()
        it("blocks if exceeding limit", function()
          for i = 1, 6 do
            local res = proxy_client():get("/response-headers?x-kong-limit=video=1, test=5", {
              headers = { Host = "test1.com" },
            })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
            assert.equal(6 - i, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
          end

          local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
            headers = { Host = "test1.com" },
          })

          assert.res_status(429, res)
        end)

        it("counts against the same service register from different routes", function()
          for i = 1, 3 do

            local res = proxy_client():get("/response-headers?x-kong-limit=video=1, test=5", {
              headers = { Host = "test-service1.com" },
            })
            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
            assert.equal(6 - i, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
          end

          for i = 4, 6 do
            local res = proxy_client():get("/response-headers?x-kong-limit=video=1, test=5", {
              headers = { Host = "test-service2.com" },
            })
            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit
            assert.res_status(200, res)
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
            assert.equal(6 - i, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
          end

          -- Additonal request, while limit is 6/minute
          local res = proxy_client():get("/response-headers?x-kong-limit=video=1, test=5", {
            headers = { Host = "test-service1.com" },
          })
          assert.res_status(429, res)
        end)

        it("handles multiple limits", function()
          for i = 1, 3 do

            local res = proxy_client():get("/response-headers?x-kong-limit=video=2, image=1", {
              headers = { Host = "test2.com" },
            })

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

            assert.res_status(200, res)
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
            assert.equal(6 - (i * 2), tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            assert.equal(10, tonumber(res.headers["x-ratelimit-limit-video-hour"]))
            assert.equal(10 - (i * 2), tonumber(res.headers["x-ratelimit-remaining-video-hour"]))
            assert.equal(4, tonumber(res.headers["x-ratelimit-limit-image-minute"]))
            assert.equal(4 - i, tonumber(res.headers["x-ratelimit-remaining-image-minute"]))
          end

          local res = proxy_client():get("/response-headers?x-kong-limit=video=2, image=1", {
            headers = { Host = "test2.com" },
          })

          assert.res_status(429, res)
          assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
          assert.equal(4, tonumber(res.headers["x-ratelimit-remaining-video-hour"]))
          assert.equal(1, tonumber(res.headers["x-ratelimit-remaining-image-minute"]))
        end)
      end)

      describe("With authentication", function()
        describe("API-specific plugin", function()
          it("blocks if exceeding limit and a per consumer & route setting", function()
            for i = 1, 2 do
              local res = proxy_client():get("/response-headers?apikey=apikey123&x-kong-limit=video=1", {
                headers = { Host = "test3.com" },
              })

              ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

              assert.res_status(200, res)
              assert.equal(2, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
              assert.equal(2 - i, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            end

            -- Third query, while limit is 2/minute
            local res = proxy_client():get("/response-headers?apikey=apikey123&x-kong-limit=video=1", {
              headers = { Host = "test3.com" },
            })
            assert.res_status(429, res)
            assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            assert.equal(2, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
          end)

          it("blocks if exceeding limit and a per consumer & route setting", function()
            for i = 1, 6 do
              local res = proxy_client():get("/response-headers?apikey=apikey124&x-kong-limit=video=1", {
                headers = { Host = "test3.com" },
              })

              ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

              assert.res_status(200, res)
              assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
              assert.equal(6 - i, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            end

            local res = proxy_client():get("/response-headers?apikey=apikey124", {
              headers = { Host = "test3.com" },
            })

            assert.res_status(200, res)
            assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
          end)

          it("blocks if exceeding limit", function()
            for i = 1, 6 do
              local res = proxy_client():get("/response-headers?apikey=apikey125&x-kong-limit=video=1", {
                headers = { Host = "test3.com" },
              })

              ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

              assert.res_status(200, res)
              assert.are.same(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
              assert.are.same(6 - i, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            end

            -- Third query, while limit is 2/minute
            local res = proxy_client():get("/response-headers?apikey=apikey125&x-kong-limit=video=1", {
              headers = { Host = "test3.com" },
            })
            assert.res_status(429, res)
            assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
          end)
        end)
      end)

      describe("Upstream usage headers", function()
        it("should append the headers with multiple limits", function()
          local res = proxy_client():get("/get", {
            headers = { Host = "test8.com" },
          })
          local json = cjson.decode(assert.res_status(200, res))
          assert.equal(4, tonumber(json.headers["x-ratelimit-remaining-image"]))
          assert.equal(6, tonumber(json.headers["x-ratelimit-remaining-video"]))

          -- Actually consume the limits
          local res = proxy_client():get("/response-headers?x-kong-limit=video=2, image=1", {
            headers = { Host = "test8.com" },
          })
          assert.res_status(200, res)

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          local res = proxy_client():get("/get", {
            headers = { Host = "test8.com" },
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.equal(3, tonumber(body.headers["x-ratelimit-remaining-image"]))
          assert.equal(4, tonumber(body.headers["x-ratelimit-remaining-video"]))
        end)

        it("combines multiple x-kong-limit headers from upstream", function()
          for i = 1, 3 do
            local res = proxy_client():get("/response-headers?x-kong-limit=video%3D2&x-kong-limit=image%3D1", {
              headers = { Host = "test4.com" },
            })

            assert.res_status(200, res)
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
            assert.equal(6 - (i * 2), tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
            assert.equal(4, tonumber(res.headers["x-ratelimit-limit-image-minute"]))
            assert.equal(4 - i, tonumber(res.headers["x-ratelimit-remaining-image-minute"]))

            ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit
          end

          local res = proxy_client():get("/response-headers?x-kong-limit=video%3D2&x-kong-limit=image%3D1", {
            headers = { Host = "test4.com" },
          })

          assert.res_status(429, res)
          assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
          assert.equal(1, tonumber(res.headers["x-ratelimit-remaining-image-minute"]))
        end)
      end)

      it("should block on first violation", function()
        local res = proxy_client():get("/response-headers?x-kong-limit=video=2, image=4", {
          headers = { Host = "test7.com" },
        })
        assert.res_status(200, res)

        ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

        local res = proxy_client():get("/response-headers?x-kong-limit=video=2", {
          headers = { Host = "test7.com" },
        })
        local body = assert.res_status(429, res)
        local json = cjson.decode(body)
        assert.same({ message = "API rate limit exceeded for 'image'" }, json)
      end)

      describe("Config with hide_client_headers", function()
        it("does not send rate-limit headers when hide_client_headers==true", function()
          local res = proxy_client():get("/status/200", {
            headers = { Host = "test9.com" },
          })

          assert.res_status(200, res)
          assert.is_nil(res.headers["x-ratelimit-remaining-video-minute"])
          assert.is_nil(res.headers["x-ratelimit-limit-video-minute"])
        end)
      end)

      if policy == "cluster" then
        describe("Fault tolerancy", function()

          before_each(function()
            helpers.kill_all()
            assert(db:truncate())

            local route1 = bp.routes:insert {
              hosts = { "failtest1.com" },
            }

            bp.response_ratelimiting_plugins:insert {
              route = { id = route1.id },
              config   = {
                fault_tolerant = false,
                policy         = policy,
                redis_host     = REDIS_HOST,
                redis_port     = REDIS_PORT,
                redis_password = REDIS_PASSWORD,
                limits         = { video = { minute = 6} },
              }
            }

            local route2 = bp.routes:insert {
              hosts = { "failtest2.com" },
            }

            bp.response_ratelimiting_plugins:insert {
              route = { id = route2.id },
              config   = {
                fault_tolerant = true,
                policy         = policy,
                redis_host     = REDIS_HOST,
                redis_port     = REDIS_PORT,
                redis_password = REDIS_PASSWORD,
                limits         = { video = {minute = 6} }
              }
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
            local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
              headers = { Host = "failtest1.com" },
            })
            assert.res_status(200, res)
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
            assert.equal(5, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))

            -- Simulate an error on the database
            assert(dao.db:drop_table("response_ratelimiting_metrics"))

            -- Make another request
            local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
              headers = { Host = "failtest1.com" },
            })
            local body = assert.res_status(500, res)
            local json = cjson.decode(body)
            assert.same({ message = "An unexpected error occurred" }, json)
          end)

          it("keeps working if an error occurs", function()
            local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
              headers = { Host = "failtest2.com" },
            })
            assert.res_status(200, res)
            assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
            assert.equal(5, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))

            -- Simulate an error on the database
            assert(dao.db:drop_table("response_ratelimiting_metrics"))

            -- Make another request
            local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
              headers = { Host = "failtest2.com" },
            })
            assert.res_status(200, res)
            assert.is_nil(res.headers["x-ratelimit-limit-video-minute"])
            assert.is_nil(res.headers["x-ratelimit-remaining-video-minute"])
          end)
        end)

      elseif policy == "redis" then
        describe("Fault tolerancy", function()

          before_each(function()
            helpers.kill_all()
            assert(db:truncate())

            local service1 = bp.services:insert()

            local route1 = bp.routes:insert {
              hosts      = { "failtest3.com" },
              protocols  = { "http", "https" },
              service    = service1
            }

            bp.response_ratelimiting_plugins:insert {
              route = { id = route1.id },
              config   = {
                fault_tolerant = false,
                policy         = policy,
                redis_host     = "5.5.5.5",
                limits         = { video = { minute = 6 } },
              }
            }

            local service2 = bp.services:insert()

            local route2 = bp.routes:insert {
              hosts      = { "failtest4.com" },
              protocols  = { "http", "https" },
              service    = service2
            }

            bp.response_ratelimiting_plugins:insert {
              route = { id = route2.id },
              config   = {
                fault_tolerant = true,
                policy         = policy,
                redis_host     = "5.5.5.5",
                limits         = { video = { minute = 6 } },
              }
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
            assert.falsy(res.headers["x-ratelimit-limit-video-minute"])
            assert.falsy(res.headers["x-ratelimit-remaining-video-minute"])
          end)
        end)
      end

      describe("Expirations", function()
        setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          local service = bp.services:insert()

          local route = bp.routes:insert {
            hosts      = { "expire1.com" },
            protocols  = { "http", "https" },
            service    = service
          }

          bp.response_ratelimiting_plugins:insert {
            route = { id = route.id },
            config   = {
              policy         = policy,
              redis_host     = REDIS_HOST,
              redis_port     = REDIS_PORT,
              redis_password = REDIS_PASSWORD,
              fault_tolerant = false,
              limits         = { video = { minute = 6 } },
            }
          }

          assert(helpers.start_kong({
            database   = strategy,
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))
        end)

        it("expires a counter", function()
          local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
            headers = { Host = "expire1.com" },
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.res_status(200, res)
          assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
          assert.equal(5, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))

          ngx.sleep(61) -- Wait for counter to expire

          local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
            headers = { Host = "expire1.com" },
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.res_status(200, res)
          assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
          assert.equal(5, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
        end)
      end)
    end)

    describe(fmt("#flaky Plugin: response-rate-limiting (access - global for single consumer) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local dao
      setup(function()
        helpers.kill_all()
        flush_redis()
        local _
        bp, _, dao = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
          "consumers",
          "keyauth_credentials",
        })
        dao.db:truncate_table("response_ratelimiting_metrics")

        local consumer = bp.consumers:insert {
          custom_id = "provider_125",
        }

        bp.key_auth_plugins:insert()

        bp.keyauth_credentials:insert {
          key         = "apikey125",
          consumer_id = consumer.id,
        }

        -- just consumer, no no route or service
        bp.response_ratelimiting_plugins:insert({
          consumer = { id = consumer.id },
          config = {
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            limits         = { video = { minute = 6 } },
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
        helpers.stop_kong()
      end)

      it("blocks when the consumer exceeds their quota, no matter what service/route used", function()
        for i = 1, 6 do
          local res = proxy_client():get("/response-headers?apikey=apikey125&x-kong-limit=video=1", {
            headers = { Host = fmt("test%d.com", i) },
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.res_status(200, res)
          assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
          assert.equal(6 - i, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
        end

        -- 7th query, while limit is 6/minute
        local res = proxy_client():get("/response-headers?apikey=apikey125&x-kong-limit=video=1", {
          headers = { Host = "test1.com" },
        })
        assert.res_status(429, res)
        assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
        assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
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
        bp.response_ratelimiting_plugins:insert({
          config = {
            fault_tolerant = false,
            policy         = policy,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            limits         = { video = { minute = 6 } },
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
          local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
            headers = { Host = fmt("test%d.com", i) },
          })

          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

          assert.res_status(200, res)
          assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
          assert.equal(6 - i, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
        end

        -- 7th query, while limit is 6/minute
        local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
          headers = { Host = "test1.com" },
        })
        assert.res_status(429, res)
        assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
        assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
      end)
    end)

  end
end
