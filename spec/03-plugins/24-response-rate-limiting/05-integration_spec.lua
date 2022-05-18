local helpers = require "spec.helpers"
local redis = require "resty.redis"
local version = require "version"
local tostring = tostring


local REDIS_HOST      = helpers.redis_host
local REDIS_PORT      = helpers.redis_port

local REDIS_DB_1 = 1
local REDIS_DB_2 = 2
local REDIS_DB_3 = 3
local REDIS_DB_4 = 4

local REDIS_USER_VALID = "response-ratelimit-user"
local REDIS_USER_INVALID = "some-user"
local REDIS_PASSWORD = "secret"

local SLEEP_TIME = 1

local function redis_connect()
  local red = redis:new()
  red:set_timeout(2000)
  assert(red:connect(REDIS_HOST, REDIS_PORT))
  local red_version = string.match(red:info(), 'redis_version:([%g]+)\r\n')
  return red, assert(version(red_version))
end

local function flush_redis(red, db)
  assert(red:select(db))
  red:flushall()
end

local function add_redis_user(red)
  assert(red:acl("setuser", REDIS_USER_VALID, "on", "allkeys", "+incrby", "+select", "+info", "+expire", "+get", "+exists", ">" .. REDIS_PASSWORD))
  assert(red:acl("setuser", REDIS_USER_INVALID, "on", "allkeys", "+get", ">" .. REDIS_PASSWORD))
end

local function remove_redis_user(red)
  assert(red:acl("deluser", REDIS_USER_VALID))
  assert(red:acl("deluser", REDIS_USER_INVALID))
end

describe("Plugin: rate-limiting (integration)", function()
  local client
  local bp
  local red
  local red_version

  lazy_setup(function()
    -- only to run migrations
    bp = helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
    }, {
      "response-ratelimiting",
    })
    red, red_version = redis_connect()

  end)

  lazy_teardown(function()
    if client then
      client:close()
    end
    if red then
      red:close()
    end

    helpers.stop_kong()
  end)

  describe("config.policy = redis", function()
    -- Regression test for the following issue:
    -- https://github.com/Kong/kong/issues/3292

    lazy_setup(function()
      flush_redis(red, REDIS_DB_1)
      flush_redis(red, REDIS_DB_2)
      flush_redis(red, REDIS_DB_3)
      if red_version >= version("6.0.0") then
        add_redis_user(red)
      end

      local route1 = assert(bp.routes:insert {
        hosts        = { "redistest1.com" },
      })
      assert(bp.plugins:insert {
        name   = "response-ratelimiting",
        route = { id = route1.id },
        config = {
          policy         = "redis",
          redis_host     = REDIS_HOST,
          redis_port     = REDIS_PORT,
          redis_database = REDIS_DB_1,
          fault_tolerant = false,
          limits         = { video = { minute = 6 } },
        },
      })

      local route2 = assert(bp.routes:insert {
        hosts        = { "redistest2.com" },
      })
      assert(bp.plugins:insert {
        name   = "response-ratelimiting",
        route = { id = route2.id },
        config = {
          policy         = "redis",
          redis_host     = REDIS_HOST,
          redis_port     = REDIS_PORT,
          redis_database = REDIS_DB_2,
          fault_tolerant = false,
          limits         = { video = { minute = 6 } },
        },
      })

      if red_version >= version("6.0.0") then
        local route3 = assert(bp.routes:insert {
          hosts        = { "redistest3.com" },
        })
        assert(bp.plugins:insert {
          name   = "response-ratelimiting",
          route = { id = route3.id },
          config = {
            policy         = "redis",
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_username = REDIS_USER_VALID,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DB_3,
            fault_tolerant = false,
            limits         = { video = { minute = 6 } },
          },
        })

        local route4 = assert(bp.routes:insert {
          hosts        = { "redistest4.com" },
        })
        assert(bp.plugins:insert {
          name   = "response-ratelimiting",
          route = { id = route4.id },
          config = {
            policy         = "redis",
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_username = REDIS_USER_INVALID,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DB_4,
            fault_tolerant = false,
            limits         = { video = { minute = 6 } },
          },
        })
      end

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if red_version >= version("6.0.0") then
        remove_redis_user(red)
      end
    end)

    it("connection pool respects database setting", function()
      assert(red:select(REDIS_DB_1))
      local size_1 = assert(red:dbsize())

      assert(red:select(REDIS_DB_2))
      local size_2 = assert(red:dbsize())

      assert.equal(0, tonumber(size_1))
      assert.equal(0, tonumber(size_2))
      if red_version >= version("6.0.0") then
        assert(red:select(REDIS_DB_3))
        local size_3 = assert(red:dbsize())
        assert.equal(0, tonumber(size_3))
      end

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
      size_1 = assert(red:dbsize())

      assert(red:select(REDIS_DB_2))
      size_2 = assert(red:dbsize())

      -- TEST: DB 1 should now have one hit, DB 2 and 3 none

      assert.is_true(tonumber(size_1) > 0)
      assert.equal(0, tonumber(size_2))
      if red_version >= version("6.0.0") then
        assert(red:select(REDIS_DB_3))
        local size_3 = assert(red:dbsize())
        assert.equal(0, tonumber(size_3))
      end

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
      size_1 = assert(red:dbsize())

      assert(red:select(REDIS_DB_2))
      size_2 = assert(red:dbsize())

      -- TEST: DB 1 and 2 should now have one hit, DB 3 none

      assert.is_true(tonumber(size_1) > 0)
      assert.is_true(tonumber(size_2) > 0)
      if red_version >= version("6.0.0") then
        assert(red:select(REDIS_DB_3))
        local size_3 = assert(red:dbsize())
        assert.equal(0, tonumber(size_3))
      end

      -- response-ratelimiting plugin reuses the redis connection
      if red_version >= version("6.0.0") then
        local res = assert(client:send {
          method = "GET",
          path = "/response-headers?x-kong-limit=video=1",
          headers = {
            ["Host"] = "redistest3.com"
          }
        })
        assert.res_status(200, res)
        assert.equal(6, tonumber(res.headers["x-ratelimit-limit-video-minute"]))
        assert.equal(5, tonumber(res.headers["x-ratelimit-remaining-video-minute"]))

        -- Wait for async timer to increment the limit

        ngx.sleep(SLEEP_TIME)

        assert(red:select(REDIS_DB_1))
        size_1 = assert(red:dbsize())

        assert(red:select(REDIS_DB_2))
        size_2 = assert(red:dbsize())

        assert(red:select(REDIS_DB_3))
        local size_3 = assert(red:dbsize())

        -- TEST: All DBs should now have one hit, because the
        -- plugin correctly chose to select the database it is
        -- configured to hit

        assert.is_true(tonumber(size_1) > 0)
        assert.is_true(tonumber(size_2) > 0)
        assert.is_true(tonumber(size_3) > 0)
      end
    end)

    it("authenticates and executes with a valid redis user having proper ACLs", function()
      if red_version >= version("6.0.0") then
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "redistest3.com"
          }
        })
        assert.res_status(200, res)
      else
        ngx.log(ngx.WARN, "Redis v" .. tostring(red_version) .. " does not support ACL functions " ..
          "'authenticates and executes with a valid redis user having proper ACLs' will be skipped")
      end
    end)

    it("fails to rate-limit for a redis user with missing ACLs", function()
      if red_version >= version("6.0.0") then
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "redistest4.com"
          }
        })
        assert.res_status(500, res)
      else
        ngx.log(ngx.WARN, "Redis v" .. tostring(red_version) .. " does not support ACL functions " ..
          "'fails to response rate-limit for a redis user with missing ACLs' will be skipped")
      end
    end)
  end)
end)
