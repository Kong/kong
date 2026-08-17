local helpers = require "spec.helpers"
local cjson = require "cjson"
local uuid = require("kong.tools.uuid").uuid


describe("Plugin: response-ratelimiting (shorthand fields)", function()
  local bp, route, admin_client
  local plugin_id = uuid()

  lazy_setup(function()
    bp = helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
    }, {
      "response-ratelimiting"
    })

    route = assert(bp.routes:insert {
      hosts = { "redis.test" },
    })

    assert(helpers.start_kong())
    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  local function assert_redis_config_same(expected_config, received_config)
  -- verify that legacy config got written into new structure
    assert.same(expected_config.redis_host, received_config.redis.host)
    assert.same(expected_config.redis_port, received_config.redis.port)
    assert.same(expected_config.redis_username, received_config.redis.username)
    assert.same(expected_config.redis_password, received_config.redis.password)
    assert.same(expected_config.redis_database, received_config.redis.database)
    assert.same(expected_config.redis_timeout, received_config.redis.timeout)
    assert.same(expected_config.redis_ssl, received_config.redis.ssl)
    assert.same(expected_config.redis_ssl_verify, received_config.redis.ssl_verify)
    assert.same(expected_config.redis_server_name, received_config.redis.server_name)

    -- verify that legacy fields are present for backwards compatibility
    assert.same(expected_config.redis_host, received_config.redis_host)
    assert.same(expected_config.redis_port, received_config.redis_port)
    assert.same(expected_config.redis_username, received_config.redis_username)
    assert.same(expected_config.redis_password, received_config.redis_password)
    assert.same(expected_config.redis_database, received_config.redis_database)
    assert.same(expected_config.redis_timeout, received_config.redis_timeout)
    assert.same(expected_config.redis_ssl, received_config.redis_ssl)
    assert.same(expected_config.redis_ssl_verify, received_config.redis_ssl_verify)
    assert.same(expected_config.redis_server_name, received_config.redis_server_name)
  end

  describe("single plugin tests", function()
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
      redis_timeout = 1100,
      redis_ssl = true,
      redis_ssl_verify = true,
      redis_server_name = "example.test",
    }

    after_each(function ()
      local res = assert(admin_client:send({
        method = "DELETE",
        path = "/plugins/" .. plugin_id,
      }))

      assert.res_status(204, res)
    end)

    it("POST/PATCH/GET request returns legacy fields", function()
      -- POST
      local res = assert(admin_client:send {
        method = "POST",
        route = {
          id = route.id
        },
        path = "/plugins",
        headers = { ["Content-Type"] = "application/json" },
        body = {
          id = plugin_id,
          name = "response-ratelimiting",
          config = plugin_config,
        },
      })

      local json = cjson.decode(assert.res_status(201, res))
      assert_redis_config_same(plugin_config, json.config)

      -- PATCH
      local updated_host = 'testhost'
      res = assert(admin_client:send {
        method = "PATCH",
        path = "/plugins/" .. plugin_id,
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "response-ratelimiting",
          config = {
            redis_host = updated_host
          },
        },
      })

      json = cjson.decode(assert.res_status(200, res))
      local patched_config = require("kong.tools.table").cycle_aware_deep_copy(plugin_config)
      patched_config.redis_host = updated_host
      assert_redis_config_same(patched_config, json.config)

      -- GET
      res = assert(admin_client:send {
        method = "GET",
        path = "/plugins/" .. plugin_id
      })

      json = cjson.decode(assert.res_status(200, res))
      assert_redis_config_same(patched_config, json.config)
    end)

    it("successful PUT request returns legacy fields", function()
      local res = assert(admin_client:send {
        method = "PUT",
        route = {
          id = route.id
        },
        path = "/plugins/" .. plugin_id,
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "response-ratelimiting",
          config = plugin_config,
        },
      })

      local json = cjson.decode(assert.res_status(200, res))
      assert_redis_config_same(plugin_config, json.config)
    end)
  end)

  describe('mutliple instances', function()
    local redis1_port = 55000
    lazy_setup(function()
      local routes_count = 100
      for i=1,routes_count do
        local route = assert(bp.routes:insert {
          name = "route-" .. tostring(i),
          hosts = { "redis" .. tostring(i) .. ".test" },
        })
        assert(bp.plugins:insert {
          name = "response-ratelimiting",
          route = { id = route.id },
          config = {
            limits = {
              video = {
                minute = 100 + i,
              }
            },
            policy = "redis",
            redis_host = "custom-host" .. tostring(i) .. ".example.test",
            redis_port = redis1_port + i,
            redis_username = "test1",
            redis_password = "testX",
            redis_database = 1,
            redis_timeout = 1100,
            redis_ssl = true,
            redis_ssl_verify = true,
            redis_server_name = "example" .. tostring(i) .. ".test",
          },
        })
      end
    end)

    it('get collection', function ()
      local res = assert(admin_client:send {
        path = "/plugins"
      })

      local json = cjson.decode(assert.res_status(200, res))
      for _,plugin in ipairs(json.data) do
        local i = plugin.config.redis.port - redis1_port
        local expected_config = {
          redis_host = "custom-host" .. tostring(i) .. ".example.test",
          redis_port =  redis1_port + i,
          redis_username =  "test1",
          redis_password =  "testX",
          redis_database =  1,
          redis_timeout =  1100,
          redis_ssl =  true,
          redis_ssl_verify =  true,
          redis_server_name =  "example" .. tostring(i) .. ".test",
        }
        assert_redis_config_same(expected_config, plugin.config)
      end
    end)

    it('get paginated collection', function ()
      local res = assert(admin_client:send {
        path = "/plugins",
        query = { size = 50 }
      })

      local json = cjson.decode(assert.res_status(200, res))
      for _,plugin in ipairs(json.data) do
        local i = plugin.config.redis.port - redis1_port
        local expected_config = {
          redis_host = "custom-host" .. tostring(i) .. ".example.test",
          redis_port =  redis1_port + i,
          redis_username =  "test1",
          redis_password =  "testX",
          redis_database =  1,
          redis_timeout =  1100,
          redis_ssl =  true,
          redis_ssl_verify =  true,
          redis_server_name =  "example" .. tostring(i) .. ".test",
        }
        assert_redis_config_same(expected_config, plugin.config)
      end
    end)


    it('get plugins by route', function ()
      local res = assert(admin_client:send {
        path = "/routes/route-1/plugins",
        query = { size = 50 }
      })

      local json = cjson.decode(assert.res_status(200, res))
      for _,plugin in ipairs(json.data) do
        local i = plugin.config.redis.port - redis1_port
        local expected_config = {
          redis_host = "custom-host" .. tostring(i) .. ".example.test",
          redis_port =  redis1_port + i,
          redis_username =  "test1",
          redis_password =  "testX",
          redis_database =  1,
          redis_timeout =  1100,
          redis_ssl =  true,
          redis_ssl_verify =  true,
          redis_server_name =  "example" .. tostring(i) .. ".test",
        }
        assert_redis_config_same(expected_config, plugin.config)
      end
    end)
  end)
end)
