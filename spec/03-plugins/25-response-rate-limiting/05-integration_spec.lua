local helpers = require "spec.helpers"
local redis = require "resty.redis"


local REDIS_HOST = "127.0.0.1"
local REDIS_PORT = 6379
local REDIS_DB_1 = 1
local REDIS_DB_2 = 2


local SLEEP_TIME = 1


local function flush_redis(db)
  local red = redis:new()
  red:set_timeout(2000)
  assert(red:connect(REDIS_HOST, REDIS_PORT))
  assert(red:select(db))
  red:flushall()
  red:close()
end


describe("Plugin: rate-limiting (integration)", function()
  local client

  setup(function()
    -- only to run migrations
    helpers.get_db_utils()
  end)

  teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
  end)

  describe("config.policy = redis", function()
    -- Regression test for the following issue:
    -- https://github.com/Kong/kong/issues/3292

    setup(function()
      flush_redis(REDIS_DB_1)
      flush_redis(REDIS_DB_2)

      local api1 = assert(helpers.dao.apis:insert {
        name         = "redistest1_com",
        hosts        = { "redistest1.com" },
        upstream_url = helpers.mock_upstream_url,
      })
      assert(helpers.dao.plugins:insert {
        name   = "response-ratelimiting",
        api_id = api1.id,
        config = {
          policy         = "redis",
          redis_host     = REDIS_HOST,
          redis_port     = REDIS_PORT,
          redis_database = REDIS_DB_1,
          fault_tolerant = false,
          limits         = { video = { minute = 6 } },
        },
      })

      local api2 = assert(helpers.dao.apis:insert {
        name         = "redistest2_com",
        hosts        = { "redistest2.com" },
        upstream_url = helpers.mock_upstream_url,
      })
      assert(helpers.dao.plugins:insert {
        name   = "response-ratelimiting",
        api_id = api2.id,
        config = {
          policy         = "redis",
          redis_host     = REDIS_HOST,
          redis_port     = REDIS_PORT,
          redis_database = REDIS_DB_2,
          fault_tolerant = false,
          limits         = { video = { minute = 6 } },
        },
      })
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      client = helpers.proxy_client()
    end)

    it("connection pool respects database setting", function()
      local red = redis:new()
      red:set_timeout(2000)

      finally(function()
        if red then
          red:close()
        end
      end)

      assert(red:connect(REDIS_HOST, REDIS_PORT))

      assert(red:select(REDIS_DB_1))
      local size_1 = assert(red:dbsize())

      assert(red:select(REDIS_DB_2))
      local size_2 = assert(red:dbsize())

      assert.equal(0, tonumber(size_1))
      assert.equal(0, tonumber(size_2))

      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=1",
        headers = {
          ["Host"] = "redistest1.com"
        }
      })
      assert.res_status(200, res)
      assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
      assert.equal(5, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))

      -- Wait for async timer to increment the limit

      ngx.sleep(SLEEP_TIME)

      assert(red:select(REDIS_DB_1))
      local size_1 = assert(red:dbsize())

      assert(red:select(REDIS_DB_2))
      local size_2 = assert(red:dbsize())

      -- TEST: DB 1 should now have one hit, DB 2 none

      assert.is_true(tonumber(size_1) > 0)
      assert.equal(0, tonumber(size_2))

      -- response-ratelimiting plugin reuses the redis connection
      local res = assert(client:send {
        method = "GET",
        path = "/response-headers?x-kong-limit=video=1",
        headers = {
          ["Host"] = "redistest2.com"
        }
      })
      assert.res_status(200, res)
      assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
      assert.equal(5, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))

      -- Wait for async timer to increment the limit

      ngx.sleep(SLEEP_TIME)

      assert(red:select(REDIS_DB_1))
      local size_1 = assert(red:dbsize())

      assert(red:select(REDIS_DB_2))
      local size_2 = assert(red:dbsize())

      -- TEST: Both DBs should now have one hit, because the
      -- plugin correctly chose to select the database it is
      -- configured to hit

      assert.is_true(tonumber(size_1) > 0)
      assert.is_true(tonumber(size_2) > 0)
    end)
  end)
end)
