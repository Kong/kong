local cjson          = require "cjson"
local helpers        = require "spec.helpers"


local REDIS_HOST     = helpers.redis_host
local REDIS_PORT     = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 1


local SLEEP_TIME = 0.01
local ITERATIONS = 10

local fmt = string.format


local proxy_client = helpers.proxy_client


local function wait()
  ngx.update_time()
  local now = ngx.now()
  local millis = (now - math.floor(now))
  ngx.sleep(1 - millis)
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


local function test_limit(path, host, limit)
  wait()
  limit = limit or ITERATIONS
  for i = 1, limit do
    local res = proxy_client():get(path, {
      headers = { Host = host:format(i) },
    })
    assert.res_status(200, res)
  end

  ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

  local res = proxy_client():get(path, {
    headers = { Host = host:format(1) },
  })
  assert.res_status(429, res)
  assert.equal(limit, tonumber(res.headers["x-ratelimit-limit-video-second"]))
  assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
end


local function init_db(strategy, policy)
  local bp = helpers.get_db_utils(strategy, {
    "routes",
    "services",
    "plugins",
    "consumers",
    "keyauth_credentials",
  })

  if policy == "redis" then
    flush_redis()
  end

  return bp
end


for _, strategy in helpers.each_strategy() do
for _, policy in ipairs({"local", "cluster", "redis"}) do

describe(fmt("#flaky Plugin: response-ratelimiting (access) with policy: #%s [#%s]", policy, strategy), function()

  lazy_setup(function()
    local bp = init_db(strategy, policy)

    if policy == "local" then
      SLEEP_TIME = 0.001
    else
      SLEEP_TIME = 0.15
    end

    local consumer1 = bp.consumers:insert {custom_id = "provider_123"}
    bp.keyauth_credentials:insert {
      key      = "apikey123",
      consumer = { id = consumer1.id },
    }

    local consumer2 = bp.consumers:insert {custom_id = "provider_124"}
    bp.keyauth_credentials:insert {
      key      = "apikey124",
      consumer = { id = consumer2.id },
    }

    local route1 = bp.routes:insert {
      hosts      = { "test1.com" },
      protocols  = { "http", "https" },
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
        limits         = { video = { second = ITERATIONS } },
      },
    })

    local route2 = bp.routes:insert {
      hosts      = { "test2.com" },
      protocols  = { "http", "https" },
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
        limits         = { video = { second = ITERATIONS*2, minute = ITERATIONS*4 },
                           image = { second = ITERATIONS } },
      },
    })

    local route3 = bp.routes:insert {
      hosts      = { "test3.com" },
      protocols  = { "http", "https" },
    }

    bp.plugins:insert {
      name     = "key-auth",
      route = { id = route3.id },
    }

    bp.response_ratelimiting_plugins:insert({
      route = { id = route3.id },
      config   = {
        policy = policy,
        redis_host     = REDIS_HOST,
        redis_port     = REDIS_PORT,
        redis_password = REDIS_PASSWORD,
        redis_database = REDIS_DATABASE,
        limits = { video = { second = ITERATIONS - 3 }
      } },
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
        limits         = { video = { second = ITERATIONS - 2 } },
      },
    })

    local route4 = bp.routes:insert {
      hosts      = { "test4.com" },
      protocols  = { "http", "https" },
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
        limits         = {
          video = { second = ITERATIONS * 2 + 2 },
          image = { second = ITERATIONS }
        },
      }
    })

    local route7 = bp.routes:insert {
      hosts      = { "test7.com" },
      protocols  = { "http", "https" },
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
            second = ITERATIONS,
            minute = ITERATIONS * 2,
          },
          image = {
            second = 4,
          },
        },
      }
    })

    local route8 = bp.routes:insert {
      hosts      = { "test8.com" },
      protocols  = { "http", "https" },
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
        limits         = { video = { second = ITERATIONS, minute = ITERATIONS*2 },
                           image = { second = ITERATIONS-1 } },
      }
    })

    local route9 = bp.routes:insert {
      hosts      = { "test9.com" },
      protocols  = { "http", "https" },
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
        limits              = { video = { second = ITERATIONS } },
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
        limits         = { video = { second = ITERATIONS } },
      }
    })

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)

  describe("Without authentication (IP address)", function()

    it("returns remaining counter", function()
      wait()
      local n = math.floor(ITERATIONS / 2)
      for _ = 1, n do
        local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
          headers = { Host = "test1.com" },
        })
        assert.res_status(200, res)
      end

      ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

      local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
        headers = { Host = "test1.com" },
      })
      assert.res_status(200, res)
      assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
      assert.equal(ITERATIONS - n - 1, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
    end)

    it("blocks if exceeding limit", function()
      test_limit("/response-headers?x-kong-limit=video=1", "test1.com")
    end)

    it("counts against the same service register from different routes", function()
      wait()
      local n = math.floor(ITERATIONS / 2)
      for i = 1, n do
        local res = proxy_client():get("/response-headers?x-kong-limit=video=1, test=" .. ITERATIONS, {
          headers = { Host = "test-service1.com" },
        })
        assert.res_status(200, res)
      end

      for i = n+1, ITERATIONS do
        local res = proxy_client():get("/response-headers?x-kong-limit=video=1, test=" .. ITERATIONS, {
          headers = { Host = "test-service2.com" },
        })
        assert.res_status(200, res)
      end

      ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the list

      -- Additonal request, while limit is ITERATIONS/second
      local res = proxy_client():get("/response-headers?x-kong-limit=video=1, test=" .. ITERATIONS, {
        headers = { Host = "test-service1.com" },
      })
      assert.res_status(429, res)
    end)

    it("handles multiple limits", function()
      wait()
      local n = math.floor(ITERATIONS / 2)
      local res
      for i = 1, n do
        if i == n then
          ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit
        end
        res = proxy_client():get("/response-headers?x-kong-limit=video=2, image=1", {
          headers = { Host = "test2.com" },
        })
        assert.res_status(200, res)
      end

      assert.equal(ITERATIONS * 2, tonumber(res.headers["x-ratelimit-limit-video-second"]))
      assert.equal(ITERATIONS * 2 - (n * 2), tonumber(res.headers["x-ratelimit-remaining-video-second"]))
      assert.equal(ITERATIONS * 4, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
      assert.equal(ITERATIONS * 4 - (n * 2), tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
      assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-image-second"]))
      assert.equal(ITERATIONS - n, tonumber(res.headers["x-ratelimit-remaining-image-second"]))

      for i = n+1, ITERATIONS do
        res = proxy_client():get("/response-headers?x-kong-limit=video=1, image=1", {
          headers = { Host = "test2.com" },
        })
        assert.res_status(200, res)
      end

      ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

      local res = proxy_client():get("/response-headers?x-kong-limit=video=1, image=1", {
        headers = { Host = "test2.com" },
      })

      assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-image-second"]))
      assert.equal(ITERATIONS * 4 - (n * 2) - (ITERATIONS - n), tonumber(res.headers["x-ratelimit-remaining-video-minute"]))
      assert.equal(ITERATIONS * 2 - (n * 2) - (ITERATIONS - n), tonumber(res.headers["x-ratelimit-remaining-video-second"]))
      assert.res_status(429, res)
    end)
  end)

  describe("With authentication", function()
    describe("API-specific plugin", function()
      it("blocks if exceeding limit and a per consumer & route setting", function()
        test_limit("/response-headers?apikey=apikey123&x-kong-limit=video=1", "test3.com", ITERATIONS - 2)
      end)

      it("blocks if exceeding limit and a per route setting", function()
        test_limit("/response-headers?apikey=apikey124&x-kong-limit=video=1", "test3.com", ITERATIONS - 3)
      end)
    end)
  end)

  describe("Upstream usage headers", function()
    it("should append the headers with multiple limits", function()
      wait()
      local res = proxy_client():get("/get", {
        headers = { Host = "test8.com" },
      })
      local json = cjson.decode(assert.res_status(200, res))
      assert.equal(ITERATIONS-1, tonumber(json.headers["x-ratelimit-remaining-image"]))
      assert.equal(ITERATIONS, tonumber(json.headers["x-ratelimit-remaining-video"]))

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
      assert.equal(ITERATIONS-2, tonumber(body.headers["x-ratelimit-remaining-image"]))
      assert.equal(ITERATIONS-2, tonumber(body.headers["x-ratelimit-remaining-video"]))
    end)

    it("combines multiple x-kong-limit headers from upstream", function()
      wait()
      for _ = 1, ITERATIONS do
        local res = proxy_client():get("/response-headers?x-kong-limit=video%3D2&x-kong-limit=image%3D1", {
          headers = { Host = "test4.com" },
        })
        assert.res_status(200, res)
      end

      proxy_client():get("/response-headers?x-kong-limit=video%3D1", {
        headers = { Host = "test4.com" },
      })

      ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

      local res = proxy_client():get("/response-headers?x-kong-limit=video%3D2&x-kong-limit=image%3D1", {
        headers = { Host = "test4.com" },
      })

      assert.res_status(429, res)
      assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-image-second"]))
      assert.equal(1, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
    end)
  end)

  it("should block on first violation", function()
    wait()
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
      wait()
      local res = proxy_client():get("/status/200", {
        headers = { Host = "test9.com" },
      })

      assert.res_status(200, res)
      assert.is_nil(res.headers["x-ratelimit-remaining-video-second"])
      assert.is_nil(res.headers["x-ratelimit-limit-video-second"])
    end)
  end)
end)

describe(fmt("#flaky Plugin: response-ratelimiting (expirations) with policy: #%s [#%s]", policy, strategy), function()

  lazy_setup(function()
    local bp = init_db(strategy, policy)

    local route = bp.routes:insert {
      hosts      = { "expire1.com" },
      protocols  = { "http", "https" },
    }

    bp.response_ratelimiting_plugins:insert {
      route = { id = route.id },
      config   = {
        policy         = policy,
        redis_host     = REDIS_HOST,
        redis_port     = REDIS_PORT,
        redis_password = REDIS_PASSWORD,
        fault_tolerant = false,
        limits         = { video = { second = ITERATIONS } },
      }
    }

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)

  it("expires a counter", function()
    wait()
    local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
      headers = { Host = "expire1.com" },
    })

    ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

    assert.res_status(200, res)
    assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
    assert.equal(ITERATIONS-1, tonumber(res.headers["x-ratelimit-remaining-video-second"]))

    ngx.sleep(0.01)
    wait() -- Wait for counter to expire

    local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
      headers = { Host = "expire1.com" },
    })

    ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

    assert.res_status(200, res)
    assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
    assert.equal(ITERATIONS-1, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
  end)
end)

describe(fmt("#flaky Plugin: response-ratelimiting (access - global for single consumer) with policy: #%s [#%s]", policy, strategy), function()

  lazy_setup(function()
    local bp = init_db(strategy, policy)

    local consumer = bp.consumers:insert {
      custom_id = "provider_126",
    }

    bp.key_auth_plugins:insert()

    bp.keyauth_credentials:insert {
      key      = "apikey126",
      consumer = { id = consumer.id },
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
        limits         = { video = { second = ITERATIONS } },
      }
    })

    for i = 1, ITERATIONS do
      bp.routes:insert({ hosts = { fmt("test%d.com", i) } })
    end

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)

  it("blocks when the consumer exceeds their quota, no matter what service/route used", function()
    test_limit("/response-headers?apikey=apikey126&x-kong-limit=video=1", "test%d.com")
  end)
end)

describe(fmt("#flaky Plugin: response-ratelimiting (access - global) with policy: #%s [#%s]", policy, strategy), function()

  lazy_setup(function()
    local bp = init_db(strategy, policy)

    -- global plugin (not attached to route, service or consumer)
    bp.response_ratelimiting_plugins:insert({
      config = {
        fault_tolerant = false,
        policy         = policy,
        redis_host     = REDIS_HOST,
        redis_port     = REDIS_PORT,
        redis_password = REDIS_PASSWORD,
        redis_database = REDIS_DATABASE,
        limits         = { video = { second = ITERATIONS } },
      }
    })

    for i = 1, ITERATIONS do
      bp.routes:insert({ hosts = { fmt("test%d.com", i) } })
    end

    assert(helpers.start_kong({
      database   = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)

  before_each(function()
    wait()
  end)

  it("blocks if exceeding limit", function()
    wait()
    for i = 1, ITERATIONS do
      local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
        headers = { Host = fmt("test%d.com", i) },
      })
      assert.res_status(200, res)
    end

    ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

    -- last query, while limit is ITERATIONS/second
    local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
      headers = { Host = "test1.com" },
    })
    assert.res_status(429, res)
    assert.equal(0, tonumber(res.headers["x-ratelimit-remaining-video-second"]))
    assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
  end)
end)

describe(fmt("#flaky Plugin: response-ratelimiting (fault tolerance) with policy: #%s [#%s]", policy, strategy), function()
  if policy == "cluster" then
    local bp, db

    pending("fault tolerance tests for cluster policy temporarily disabled", function()

      before_each(function()
        bp, db = init_db(strategy, policy)

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
            limits         = { video = { second = ITERATIONS} },
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
            limits         = { video = {second = ITERATIONS} }
          }
        }

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        wait()
      end)

      after_each(function()
        helpers.stop_kong(nil, true)
      end)

      it("does not work if an error occurs", function()
        local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
          headers = { Host = "failtest1.com" },
        })
        assert.res_status(200, res)
        assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
        assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-remaining-video-second"]))

        -- Simulate an error on the database
        -- (valid SQL and CQL)
        db.connector:query("DROP TABLE response_ratelimiting_metrics;")
        -- FIXME this leaves the database in a bad state after this test,
        -- affecting subsequent tests.

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
        assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-limit-video-second"]))
        assert.equal(ITERATIONS, tonumber(res.headers["x-ratelimit-remaining-video-second"]))

        -- Simulate an error on the database
        -- (valid SQL and CQL)
        db.connector:query("DROP TABLE response_ratelimiting_metrics;")
        -- FIXME this leaves the database in a bad state after this test,
        -- affecting subsequent tests.

        -- Make another request
        local res = proxy_client():get("/response-headers?x-kong-limit=video=1", {
          headers = { Host = "failtest2.com" },
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["x-ratelimit-limit-video-second"])
        assert.is_nil(res.headers["x-ratelimit-remaining-video-second"])
      end)
    end)
  end

  if policy == "redis" then

    before_each(function()
      local bp = init_db(strategy, policy)

      local route1 = bp.routes:insert {
        hosts      = { "failtest3.com" },
        protocols  = { "http", "https" },
      }

      bp.response_ratelimiting_plugins:insert {
        route = { id = route1.id },
        config   = {
          fault_tolerant = false,
          policy         = policy,
          redis_host     = "5.5.5.5",
          limits         = { video = { second = ITERATIONS } },
        }
      }

      local route2 = bp.routes:insert {
        hosts      = { "failtest4.com" },
        protocols  = { "http", "https" },
      }

      bp.response_ratelimiting_plugins:insert {
        route = { id = route2.id },
        config   = {
          fault_tolerant = true,
          policy         = policy,
          redis_host     = "5.5.5.5",
          limits         = { video = { second = ITERATIONS } },
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      wait()
    end)

    after_each(function()
      helpers.stop_kong(nil, true)
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
      assert.falsy(res.headers["x-ratelimit-limit-video-second"])
      assert.falsy(res.headers["x-ratelimit-remaining-video-second"])
    end)
  end
end)

end
end
