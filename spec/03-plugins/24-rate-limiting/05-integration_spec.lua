local helpers = require "spec.helpers"
local redis = require "resty.redis"

local REDIS_HOST = "127.0.0.1"
local REDIS_PORT = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 1
local REDIS_DATABASE_SECOND = 0

local SLEEP_TIME = 1

local function flush_redis(db)
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

  local ok, err = red:select(db)
  if not ok then
    error("failed to change Redis database: " .. err)
  end

  red:flushall()
  red:close()
end

describe("Plugin: rate-limiting (integration)", function()

  local client

  setup(function()
    helpers.run_migrations()
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("Redis conn select database", function()
    -- Regression test for the following issue:
    -- https://github.com/Kong/kong/issues/3292

    setup(function()
      flush_redis(REDIS_DATABASE)
      flush_redis(REDIS_DATABASE_SECOND)
      local api1 = assert(helpers.dao.apis:insert {
        name         = "redistest1_com",
        hosts        = { "redistest1.com" },
        upstream_url = helpers.mock_upstream_url,
      })
      assert(helpers.dao.plugins:insert {
        name   = "rate-limiting",
        api_id = api1.id,
        config = {
          minute              = 1,
          policy              = "redis",
          redis_host          = REDIS_HOST,
          redis_port          = REDIS_PORT,
          redis_password      = REDIS_PASSWORD,
          redis_database      = REDIS_DATABASE,
          fault_tolerant      = false
        },
      })

      local api2 = assert(helpers.dao.apis:insert {
        name         = "redistest2_com",
        hosts        = { "redistest2.com" },
        upstream_url = helpers.mock_upstream_url,
      })
      assert(helpers.dao.plugins:insert {
        name   = "rate-limiting",
        api_id = api2.id,
        config = {
          minute              = 1,
          policy              = "redis",
          redis_host          = REDIS_HOST,
          redis_port          = REDIS_PORT,
          redis_password      = REDIS_PASSWORD,
          redis_database      = REDIS_DATABASE_SECOND,
          fault_tolerant      = false
        }
      })
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      client = helpers.proxy_client()
    end)

    it("redis conn select databases", function()
      local red = redis:new()
      red:set_timeout(2000)
      assert(red:connect(REDIS_HOST, REDIS_PORT))
      if REDIS_PASSWORD and REDIS_PASSWORD ~= "" then
        assert(red:auth(REDIS_PASSWORD))
      end
      assert(red:select(REDIS_DATABASE))
      local val1, err = red:dbsize()
      if err then
        error("failed to call dbsize: " .. err)
      end
      assert(red:select(REDIS_DATABASE_SECOND))
      local val2, err = red:dbsize()
      if err then
        error("failed to call dbsize: " .. err)
      end
      assert.are.same(0, tonumber(val1))
      assert.are.same(0, tonumber(val2))

      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "redistest1.com"
        }
      })
      assert.res_status(200, res)
      ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

      assert(red:select(REDIS_DATABASE))
      local val1, err = red:dbsize()
      if err then
        error("failed to call dbsize: " .. err)
      end
      assert(red:select(REDIS_DATABASE_SECOND))
      local val2, err = red:dbsize()
      if err then
        error("failed to call dbsize: " .. err)
      end
      assert.are.same(1, tonumber(val1))
      assert.are.same(0, tonumber(val2))

      -- rate-limiting plugin reuse api1 redis connection
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "redistest2.com"
        }
      })
      assert.res_status(200, res)
      ngx.sleep(SLEEP_TIME) -- Wait for async timer to increment the limit

      assert(red:select(REDIS_DATABASE))
      local val1, err = red:dbsize()
      if err then
        error("failed to call dbsize: " .. err)
      end
      assert(red:select(REDIS_DATABASE_SECOND))
      local val2, err = red:dbsize()
      if err then
        error("failed to call dbsize: " .. err)
      end
      red:close()
      assert.are.same(1, tonumber(val1))
      assert.are.same(1, tonumber(val2))
    end)
  end)
end)
