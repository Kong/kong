local helpers = require "spec.helpers"
local redis = require "resty.redis"


local REDIS_HOST = helpers.redis_host
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
  local bp

  lazy_setup(function()
    bp = helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
    }, {
      "rate-limiting"
    })
  end)

  lazy_teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
  end)

  describe("config.policy = redis", function()
    -- Regression test for the following issue:
    -- https://github.com/Kong/kong/issues/3292

    lazy_setup(function()
      flush_redis(REDIS_DB_1)
      flush_redis(REDIS_DB_2)

      local route1 = assert(bp.routes:insert {
        hosts        = { "redistest1.com" },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting",
        route = { id = route1.id },
        config = {
          minute         = 1,
          policy         = "redis",
          redis_host     = REDIS_HOST,
          redis_port     = REDIS_PORT,
          redis_database = REDIS_DB_1,
          fault_tolerant = false,
        },
      })

      local route2 = assert(bp.routes:insert {
        hosts        = { "redistest2.com" },
      })
      assert(bp.plugins:insert {
        name = "rate-limiting",
        route = { id = route2.id },
        config = {
          minute         = 1,
          policy         = "redis",
          redis_host     = REDIS_HOST,
          redis_port     = REDIS_PORT,
          redis_database = REDIS_DB_2,
          fault_tolerant = false,
        }
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
        path = "/status/200",
        headers = {
          ["Host"] = "redistest1.com"
        }
      })
      assert.res_status(200, res)

      -- Wait for async timer to increment the limit

      ngx.sleep(SLEEP_TIME)

      assert(red:select(REDIS_DB_1))
      size_1 = assert(red:dbsize())

      assert(red:select(REDIS_DB_2))
      size_2 = assert(red:dbsize())

      -- TEST: DB 1 should now have one hit, DB 2 none

      assert.equal(1, tonumber(size_1))
      assert.equal(0, tonumber(size_2))

      -- rate-limiting plugin will reuses the redis connection
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "redistest2.com"
        }
      })
      assert.res_status(200, res)

      -- Wait for async timer to increment the limit

      ngx.sleep(SLEEP_TIME)

      assert(red:select(REDIS_DB_1))
      size_1 = assert(red:dbsize())

      assert(red:select(REDIS_DB_2))
      size_2 = assert(red:dbsize())

      -- TEST: Both DBs should now have one hit, because the
      -- plugin correctly chose to select the database it is
      -- configured to hit

      assert.equal(1, tonumber(size_1))
      assert.equal(1, tonumber(size_2))
    end)
  end)
end)
