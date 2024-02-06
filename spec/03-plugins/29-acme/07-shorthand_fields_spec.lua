local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"


describe("Plugin: acme (shorthand fields)", function()
  local bp, route, admin_client
  local plugin_id = utils.uuid()

  lazy_setup(function()
    bp = helpers.get_db_utils(nil, {
      "routes",
      "services",
      "plugins",
    }, {
      "acme"
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
    assert.same(expected_config.host, received_config.storage_config.redis.host)
    assert.same(expected_config.port, received_config.storage_config.redis.port)
    assert.same(expected_config.auth, received_config.storage_config.redis.password)
    assert.same(expected_config.database, received_config.storage_config.redis.database)
    assert.same(expected_config.timeout, received_config.storage_config.redis.timeout)
    assert.same(expected_config.ssl, received_config.storage_config.redis.ssl)
    assert.same(expected_config.ssl_verify, received_config.storage_config.redis.ssl_verify)
    assert.same(expected_config.ssl_server_name, received_config.storage_config.redis.server_name)
    assert.same(expected_config.scan_count, received_config.storage_config.redis.extra_options.scan_count)
    assert.same(expected_config.namespace, received_config.storage_config.redis.extra_options.namespace)

    -- verify that legacy fields are present for backwards compatibility
    assert.same(expected_config.auth, received_config.storage_config.redis.auth)
    assert.same(expected_config.ssl_server_name, received_config.storage_config.redis.ssl_server_name)
    assert.same(expected_config.scan_count, received_config.storage_config.redis.scan_count)
    assert.same(expected_config.namespace, received_config.storage_config.redis.namespace)
  end

  describe("single plugin tests", function()
    local redis_config = {
      host = helpers.redis_host,
      port = helpers.redis_port,
      auth = "test",
      database = 1,
      timeout = 3500,
      ssl = true,
      ssl_verify = true,
      ssl_server_name = "example.test",
      scan_count = 13,
      namespace = "namespace2:",
    }

    local plugin_config = {
      account_email = "test@test.com",
      storage = "redis",
      storage_config = {
        redis = redis_config,
      },
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
          name = "acme",
          config = plugin_config,
        },
      })

      local json = cjson.decode(assert.res_status(201, res))
      assert_redis_config_same(redis_config, json.config)

      -- PATCH
      local updated_host = 'testhost'
      res = assert(admin_client:send {
        method = "PATCH",
        path = "/plugins/" .. plugin_id,
        headers = { ["Content-Type"] = "application/json" },
        body = {
          name = "acme",
          config = {
            storage_config = {
              redis = {
                host = updated_host
              }
            }
          },
        },
      })

      json = cjson.decode(assert.res_status(200, res))
      local patched_config = utils.cycle_aware_deep_copy(redis_config)
      patched_config.host = updated_host
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
          name = "acme",
          config = plugin_config,
        },
      })

      local json = cjson.decode(assert.res_status(200, res))
      assert_redis_config_same(redis_config, json.config)
    end)
  end)
end)
