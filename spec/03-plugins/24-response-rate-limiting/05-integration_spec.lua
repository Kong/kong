local helpers = require "spec.helpers"
local redis = require "resty.redis"
local version = require "version"
local cjson = require "cjson"
local tostring = tostring


local REDIS_HOST      = helpers.redis_host
local REDIS_PORT      = helpers.redis_port
local REDIS_SSL_PORT  = helpers.redis_ssl_port
local REDIS_SSL_SNI   = helpers.redis_ssl_sni

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

  local strategies = {
    no_ssl = {
      redis_port = REDIS_PORT,
    },
    ssl_verify = {
      redis_ssl = true,
      redis_ssl_verify = true,
      redis_server_name = REDIS_SSL_SNI,
      lua_ssl_trusted_certificate = "spec/fixtures/redis/ca.crt",
      redis_port = REDIS_SSL_PORT,
    },
    ssl_no_verify = {
      redis_ssl = true,
      redis_ssl_verify = false,
      redis_server_name = "really.really.really.does.not.exist.host.test",
      redis_port = REDIS_SSL_PORT,
    },
  }

  for strategy, config in pairs(strategies) do

    describe("config.policy = redis #" .. strategy, function()
      -- Regression test for the following issue:
      -- https://github.com/Kong/kong/issues/3292

      lazy_setup(function()
        flush_redis(red, REDIS_DB_1)
        flush_redis(red, REDIS_DB_2)
        flush_redis(red, REDIS_DB_3)
        if red_version >= version("6.0.0") then
          add_redis_user(red)
        end

        bp = helpers.get_db_utils(nil, {
          "routes",
          "services",
          "plugins",
        }, {
          "response-ratelimiting",
        })

        local route1 = assert(bp.routes:insert {
          hosts        = { "redistest1.test" },
        })
        assert(bp.plugins:insert {
          name   = "response-ratelimiting",
          route = { id = route1.id },
          config = {
            policy            = "redis",
            redis = {
              host        = REDIS_HOST,
              port        = config.redis_port,
              database    = REDIS_DB_1,
              ssl         = config.redis_ssl,
              ssl_verify  = config.redis_ssl_verify,
              server_name = config.redis_server_name,
              timeout     = 10000,
            },
            fault_tolerant    = false,
            limits            = { video = { minute = 6 } },
          },
        })

        local route2 = assert(bp.routes:insert {
          hosts        = { "redistest2.test" },
        })
        assert(bp.plugins:insert {
          name   = "response-ratelimiting",
          route = { id = route2.id },
          config = {
            policy            = "redis",
            redis = {
              host        = REDIS_HOST,
              port        = config.redis_port,
              database    = REDIS_DB_2,
              ssl         = config.redis_ssl,
              ssl_verify  = config.redis_ssl_verify,
              server_name = config.redis_server_name,
              timeout     = 10000,
            },
            fault_tolerant    = false,
            limits            = { video = { minute = 6 } },
          },
        })

        if red_version >= version("6.0.0") then
          local route3 = assert(bp.routes:insert {
            hosts        = { "redistest3.test" },
          })
          assert(bp.plugins:insert {
            name   = "response-ratelimiting",
            route = { id = route3.id },
            config = {
              policy            = "redis",
              redis = {
                host        = REDIS_HOST,
                port        = config.redis_port,
                username    = REDIS_USER_VALID,
                password    = REDIS_PASSWORD,
                database    = REDIS_DB_3,
                ssl         = config.redis_ssl,
                ssl_verify  = config.redis_ssl_verify,
                server_name = config.redis_server_name,
                timeout     = 10000,
              },
              fault_tolerant    = false,
              limits            = { video = { minute = 6 } },
            },
          })

          local route4 = assert(bp.routes:insert {
            hosts        = { "redistest4.test" },
          })
          assert(bp.plugins:insert {
            name   = "response-ratelimiting",
            route = { id = route4.id },
            config = {
              policy            = "redis",
              redis = {
                host        = REDIS_HOST,
                port        = config.redis_port,
                username    = REDIS_USER_INVALID,
                password    = REDIS_PASSWORD,
                database    = REDIS_DB_4,
                ssl         = config.redis_ssl,
                ssl_verify  = config.redis_ssl_verify,
                server_name = config.redis_server_name,
                timeout     = 10000,
              },
              fault_tolerant    = false,
              limits            = { video = { minute = 6 } },
            },
          })
        end

        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
          lua_ssl_trusted_certificate = config.lua_ssl_trusted_certificate,
        }))
        client = helpers.proxy_client()
      end)

      lazy_teardown(function()
        helpers.stop_kong()
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
            ["Host"] = "redistest1.test"
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
            ["Host"] = "redistest2.test"
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
              ["Host"] = "redistest3.test"
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
              ["Host"] = "redistest3.test"
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
              ["Host"] = "redistest4.test"
            }
          })
          assert.res_status(500, res)
        else
          ngx.log(ngx.WARN, "Redis v" .. tostring(red_version) .. " does not support ACL functions " ..
            "'fails to response rate-limit for a redis user with missing ACLs' will be skipped")
        end
      end)
    end)
  end -- end for each strategy

  describe("creating rate-limiting plugins using api", function ()
    local route3, admin_client

    lazy_setup(function()
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template"
      }))

      route3 = assert(bp.routes:insert {
        hosts        = { "redistest3.test" },
      })

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end

      helpers.stop_kong()
    end)

    before_each(function()
      helpers.clean_logfile()
    end)

    local function delete_plugin(admin_client, plugin)
      local res = assert(admin_client:send({
        method = "DELETE",
        path = "/plugins/" .. plugin.id,
      }))

      assert.res_status(204, res)
    end

    it("allows to create a plugin with new redis configuration", function()
      local redis_config = {
        host = helpers.redis_host,
        port = helpers.redis_port,
        username = "test1",
        password = "testX",
        database = 1,
        timeout = 1100,
        ssl = true,
        ssl_verify = true,
        server_name = "example.test",
      }
      local res = assert(admin_client:send {
        method = "POST",
        route = {
          id = route3.id
        },
        path = "/plugins",
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "response-ratelimiting",
          config = {
            limits = {
              video = {
                minute = 100,
              }
            },
            policy = "redis",
            redis = redis_config,
          },
        },
      })

      local json = cjson.decode(assert.res_status(201, res))

      -- verify that legacy defaults don't ovewrite new structure when they were not defined
      assert.same(redis_config.host, json.config.redis.host)
      assert.same(redis_config.port, json.config.redis.port)
      assert.same(redis_config.username, json.config.redis.username)
      assert.same(redis_config.password, json.config.redis.password)
      assert.same(redis_config.database, json.config.redis.database)
      assert.same(redis_config.timeout, json.config.redis.timeout)
      assert.same(redis_config.ssl, json.config.redis.ssl)
      assert.same(redis_config.ssl_verify, json.config.redis.ssl_verify)
      assert.same(redis_config.server_name, json.config.redis.server_name)

      delete_plugin(admin_client, json)

      assert.logfile().has.no.line("response-ratelimiting: config.redis_host is deprecated, please use config.redis.host instead (deprecated after 4.0)", true)
      assert.logfile().has.no.line("response-ratelimiting: config.redis_port is deprecated, please use config.redis.port instead (deprecated after 4.0)", true)
      assert.logfile().has.no.line("response-ratelimiting: config.redis_password is deprecated, please use config.redis.password instead (deprecated after 4.0)", true)
      assert.logfile().has.no.line("response-ratelimiting: config.redis_username is deprecated, please use config.redis.username instead (deprecated after 4.0)", true)
      assert.logfile().has.no.line("response-ratelimiting: config.redis_ssl is deprecated, please use config.redis.ssl instead (deprecated after 4.0)", true)
      assert.logfile().has.no.line("response-ratelimiting: config.redis_ssl_verify is deprecated, please use config.redis.ssl_verify instead (deprecated after 4.0)", true)
      assert.logfile().has.no.line("response-ratelimiting: config.redis_server_name is deprecated, please use config.redis.server_name instead (deprecated after 4.0)", true)
      assert.logfile().has.no.line("response-ratelimiting: config.redis_timeout is deprecated, please use config.redis.timeout instead (deprecated after 4.0)", true)
      assert.logfile().has.no.line("response-ratelimiting: config.redis_database is deprecated, please use config.redis.database instead (deprecated after 4.0)", true)
    end)

    it("allows to create a plugin with legacy redis configuration", function()
      local plugin_config = {
        limits = {
          video = {
            minute = 100,
          }
        },
        policy = "redis",
        redis_host = "custom-host.example.test",
        redis_port = 55000,
        redis_username = "test1",
        redis_password = "testX",
        redis_database = 1,
        redis_timeout = 3400,
        redis_ssl = true,
        redis_ssl_verify = true,
        redis_server_name = "example.test",
      }
      local res = assert(admin_client:send {
        method = "POST",
        route = {
          id = route3.id
        },
        path = "/plugins",
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "response-ratelimiting",
          config = plugin_config,
        },
      })

      local json = cjson.decode(assert.res_status(201, res))

      -- verify that legacy config got written into new structure
      assert.same(plugin_config.redis_host, json.config.redis.host)
      assert.same(plugin_config.redis_port, json.config.redis.port)
      assert.same(plugin_config.redis_username, json.config.redis.username)
      assert.same(plugin_config.redis_password, json.config.redis.password)
      assert.same(plugin_config.redis_database, json.config.redis.database)
      assert.same(plugin_config.redis_timeout, json.config.redis.timeout)
      assert.same(plugin_config.redis_ssl, json.config.redis.ssl)
      assert.same(plugin_config.redis_ssl_verify, json.config.redis.ssl_verify)
      assert.same(plugin_config.redis_server_name, json.config.redis.server_name)

      -- verify that legacy fields are present for backwards compatibility
      assert.same(plugin_config.redis_host, json.config.redis_host)
      assert.same(plugin_config.redis_port, json.config.redis_port)
      assert.same(plugin_config.redis_username, json.config.redis_username)
      assert.same(plugin_config.redis_password, json.config.redis_password)
      assert.same(plugin_config.redis_database, json.config.redis_database)
      assert.same(plugin_config.redis_timeout, json.config.redis_timeout)
      assert.same(plugin_config.redis_ssl, json.config.redis_ssl)
      assert.same(plugin_config.redis_ssl_verify, json.config.redis_ssl_verify)
      assert.same(plugin_config.redis_server_name, json.config.redis_server_name)

      delete_plugin(admin_client, json)

      assert.logfile().has.line("response-ratelimiting: config.redis_host is deprecated, please use config.redis.host instead (deprecated after 4.0)", true)
      assert.logfile().has.line("response-ratelimiting: config.redis_port is deprecated, please use config.redis.port instead (deprecated after 4.0)", true)
      assert.logfile().has.line("response-ratelimiting: config.redis_password is deprecated, please use config.redis.password instead (deprecated after 4.0)", true)
      assert.logfile().has.line("response-ratelimiting: config.redis_username is deprecated, please use config.redis.username instead (deprecated after 4.0)", true)
      assert.logfile().has.line("response-ratelimiting: config.redis_ssl is deprecated, please use config.redis.ssl instead (deprecated after 4.0)", true)
      assert.logfile().has.line("response-ratelimiting: config.redis_ssl_verify is deprecated, please use config.redis.ssl_verify instead (deprecated after 4.0)", true)
      assert.logfile().has.line("response-ratelimiting: config.redis_server_name is deprecated, please use config.redis.server_name instead (deprecated after 4.0)", true)
      assert.logfile().has.line("response-ratelimiting: config.redis_timeout is deprecated, please use config.redis.timeout instead (deprecated after 4.0)", true)
      assert.logfile().has.line("response-ratelimiting: config.redis_database is deprecated, please use config.redis.database instead (deprecated after 4.0)", true)
    end)
  end)
end)
