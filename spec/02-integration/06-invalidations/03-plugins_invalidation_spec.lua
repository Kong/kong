local cjson   = require "cjson"
local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"


local POLL_INTERVAL = 1


for _, strategy in helpers.each_strategy() do
  describe("plugins with db [#" .. strategy .. "]", function()

    local admin_client_1
    local admin_client_2

    local proxy_client_1
    local proxy_client_2

    local wait_for_propagation

    local service_fixture

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "apis",
        "routes",
        "services",
        "plugins",
        "certificates",
      })

      -- insert single fixture Service
      service_fixture = bp.services:insert()

      local db_update_propagation = strategy == "cassandra" and 0.1 or 0

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot1",
        database              = strategy,
        proxy_listen          = "0.0.0.0:8000, 0.0.0.0:8443 ssl",
        admin_listen          = "0.0.0.0:8001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
        nginx_conf            = "spec/fixtures/custom_nginx.template",
      })

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot2",
        database              = strategy,
        proxy_listen          = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
        admin_listen          = "0.0.0.0:9001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
      })

      local admin_client = helpers.http_client("127.0.0.1", 8001)
      local admin_res = assert(admin_client:send {
        method  = "POST",
        path    = "/routes",
        body    = {
          protocols = { "http" },
          hosts     = { "dummy.com" },
          service   = {
            id = service_fixture.id,
          }
        },
        headers = {
          ["Content-Type"] = "application/json",
        },
      })
      assert.res_status(201, admin_res)
      admin_client:close()

      wait_for_propagation = function()
        ngx.sleep(POLL_INTERVAL * 2 + db_update_propagation * 2)
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot1")
      helpers.stop_kong("servroot2")
    end)

    before_each(function()
      admin_client_1 = helpers.http_client("127.0.0.1", 8001)
      admin_client_2 = helpers.http_client("127.0.0.1", 9001)
      proxy_client_1 = helpers.http_client("127.0.0.1", 8000)
      proxy_client_2 = helpers.http_client("127.0.0.1", 9000)
    end)

    after_each(function()
      admin_client_1:close()
      admin_client_2:close()
      proxy_client_1:close()
      proxy_client_2:close()
    end)

    describe("plugins:version", function()
      local service_plugin_id

      it("is created at startup", function()
        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })
        local body_1 = assert.res_status(200, admin_res_1)
        local json_1 = cjson.decode(body_1)

        local admin_res_2 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })
        local body_2 = assert.res_status(200, admin_res_2)
        local json_2 = cjson.decode(body_2)

        assert.equal("init", json_1.message)
        assert.equal("init", json_2.message)
      end)

      it("is invalidated on plugin creation", function()
        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })
        local body_1 = assert.res_status(200, admin_res_1)
        local json_1 = cjson.decode(body_1)

        local admin_res_2 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })
        local body_2 = assert.res_status(200, admin_res_2)
        local json_2 = cjson.decode(body_2)

        assert.equal("init", json_1.message)
        assert.equal("init", json_2.message)

        -- create Plugin
        local admin_res_plugin = assert(admin_client_1:send {
          method = "POST",
          path   = "/plugins",
          body   = {
            name    = "dummy",
            service = { id = service_fixture.id },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.res_status(201, admin_res_plugin)
        local plugin = cjson.decode(body)

        service_plugin_id = plugin.id

        wait_for_propagation()

        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })

        local body_1 = assert.res_status(200, admin_res_1)
        local json_1 = cjson.decode(body_1)

        local admin_res_2 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })
        local body_2 = assert.res_status(200, admin_res_2)
        local json_2 = cjson.decode(body_2)

        assert.matches("^[%w-]+$", json_1.message)
        assert.matches("^[%w-]+$", json_2.message)

        assert.not_equal("init", json_1.message)
        assert.not_equal("init", json_2.message)
        assert.not_equal(json_1.message, json_2.message)
      end)

      it("is created on proxied request", function()
        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)

        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })
        local body_1 = assert.res_status(200, admin_res_1)
        local json_1 = cjson.decode(body_1)

        local admin_res_2 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })
        local body_2 = assert.res_status(200, admin_res_2)
        local json_2 = cjson.decode(body_2)

        assert.matches("^[%w-]+$", json_1.message)
        assert.matches("^[%w-]+$", json_2.message)

        assert.not_equal("init", json_1.message)
        assert.not_equal("init", json_2.message)
        assert.not_equal(json_1.message, json_2.message)
      end)

      it("is invalidated on plugin PATCH", function()
        local admin_res_plugin = assert(admin_client_1:send {
          method = "PATCH",
          path   = "/plugins/" .. service_plugin_id,
          body   = {
            ["config.resp_header_value"] = "2",
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(200, admin_res_plugin)

        wait_for_propagation()

        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })

        local body_1 = assert.res_status(200, admin_res_1)
        local json_1 = cjson.decode(body_1)

        local admin_res_2 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })

        local body_2 = assert.res_status(200, admin_res_2)
        local json_2 = cjson.decode(body_2)

        assert.matches("^[%w-]+$", json_1.message)
        assert.matches("^[%w-]+$", json_2.message)

        assert.not_equal("init", json_1.message)
        assert.not_equal("init", json_2.message)
        assert.not_equal(json_1.message, json_2.message)
      end)

      it("is invalidated on plugin delete", function()
        local admin_res_plugin = assert(admin_client_1:send {
          method = "DELETE",
          path   = "/plugins/" .. service_plugin_id,
        })
        assert.res_status(204, admin_res_plugin)

        wait_for_propagation()

        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })

        local body_1 = assert.res_status(200, admin_res_1)
        local json_1 = cjson.decode(body_1)

        local admin_res_2 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })

        local body_2 = assert.res_status(200, admin_res_2)
        local json_2 = cjson.decode(body_2)

        assert.matches("^[%w-]+$", json_1.message)
        assert.matches("^[%w-]+$", json_2.message)

        assert.not_equal("init", json_1.message)
        assert.not_equal("init", json_2.message)
        assert.not_equal(json_1.message, json_2.message)
      end)

      it("is invalidated on plugin PUT", function()
        -- A regression test for https://github.com/Kong/kong/issues/4191
        local admin_res_plugin = assert(admin_client_1:send {
          method = "PUT",
          path   = "/plugins/" .. utils.uuid(),
          body   = {
            name    = "dummy",
            service = { id = service_fixture.id },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(200, admin_res_plugin)

        wait_for_propagation()

        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })

        local body_1 = assert.res_status(200, admin_res_1)
        local json_1 = cjson.decode(body_1)

        local admin_res_2 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins:version",
        })

        local body_2 = assert.res_status(200, admin_res_2)
        local json_2 = cjson.decode(body_2)

        assert.matches("^[%w-]+$", json_1.message)
        assert.matches("^[%w-]+$", json_2.message)

        assert.not_equal("init", json_1.message)
        assert.not_equal("init", json_2.message)
        assert.not_equal(json_1.message, json_2.message)
      end)
    end)
  end)
end
