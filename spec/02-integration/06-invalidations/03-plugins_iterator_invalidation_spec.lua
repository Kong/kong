local cjson   = require "cjson"
local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"


local POLL_INTERVAL = 0.3


local function assert_admin_2_wait(request, res_status, res_not_message)
  local ret
  helpers.wait_until(function()
    local admin_client_2 = helpers.http_client("127.0.0.1", 9001)
    finally(function()
      admin_client_2:close()
    end)

    local res = admin_client_2:send(request)
    if not res then
      return false
    end
    if res.status ~= res_status then
      return false
    end
    local body = res:read_body()
    if not body then
      return false
    end
    local json = cjson.decode(body)
    if res_not_message then
      if not json.message:match("^[%w-]+$") then
        return false
      end
      if json.message == res_not_message then
        return false
      end
    end
    ret = json
    return true
  end, 10)
  return ret
end


for _, strategy in helpers.each_strategy() do
  describe("plugins iterator with db [#" .. strategy .. "]", function()

    local admin_client_1
    local admin_client_2

    local proxy_client_1
    local proxy_client_2

    local service_fixture

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
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
        router_update_frequency = POLL_INTERVAL,
      })

      assert(helpers.start_kong {
        log_level             = "debug",
        prefix                = "servroot2",
        database              = strategy,
        proxy_listen          = "0.0.0.0:9000, 0.0.0.0:9443 ssl",
        admin_listen          = "0.0.0.0:9001",
        db_update_frequency   = POLL_INTERVAL,
        db_update_propagation = db_update_propagation,
        router_update_frequency = POLL_INTERVAL,
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

    describe("plugins_iterator:version", function()
      local service_plugin_id

      it("is created at startup", function()
        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins_iterator:version",
        })
        local body_1 = assert.res_status(200, admin_res_1)
        local msg_1  = cjson.decode(body_1)

        local admin_res_2 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins_iterator:version",
        })
        local body_2 = assert.res_status(200, admin_res_2)
        local msg_2  = cjson.decode(body_2)

        assert.equal("init", msg_1.message)
        assert.equal("init", msg_2.message)
      end)

      it("changes on plugin creation", function()
        local admin_res_before = admin_client_2:get("/cache/plugins_iterator:version")
        local body_before = assert.res_status(200, admin_res_before)
        local msg_before  = cjson.decode(body_before)
        assert.matches("^[%w-]+$", msg_before.message)

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

        assert_admin_2_wait({
          method = "GET",
          path = "/cache/plugins_iterator:version",
        }, 200, msg_before.message)
      end)

      it("changes on proxied request or timer", function()
        -- issue a request
        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_1)

        local admin_res_1 = assert(admin_client_1:send {
          method = "GET",
          path   = "/cache/plugins_iterator:version",
        })
        local body_1 = assert.res_status(200, admin_res_1)
        local msg_1  = cjson.decode(body_1)

        assert.matches("^[%w-]+$", msg_1.message)

        -- each node has their own version
        local msg_2 = assert_admin_2_wait({
          method = "GET",
          path = "/cache/plugins_iterator:version",
        }, 200)

        -- check that node 2 was already up to date via its timer
        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            host = "dummy.com",
          }
        })
        assert.res_status(200, res_2)

        local admin_res_3 = assert(admin_client_2:send {
          method = "GET",
          path   = "/cache/plugins_iterator:version",
        })
        local body_3 = assert.res_status(200, admin_res_3)
        local msg_3  = cjson.decode(body_3)
        assert.matches("^[%w-]+$", msg_3.message)

        -- no version change
        assert.equals(msg_2.message, msg_3.message)
      end)

      it("changes on plugin PATCH", function()
        local admin_res_before = admin_client_2:get("/cache/plugins_iterator:version")
        local body_before = assert.res_status(200, admin_res_before)
        local msg_before  = cjson.decode(body_before)
        assert.matches("^[%w-]+$", msg_before.message)

        local admin_res_plugin = assert(admin_client_1:send {
          method = "PATCH",
          path   = "/plugins/" .. service_plugin_id,
          body   = {
            config = {
              resp_header_value = "2"
            }
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.res_status(200, admin_res_plugin)

        -- the version has changed
        assert_admin_2_wait({
          method = "GET",
          path = "/cache/plugins_iterator:version",
        }, 200, msg_before.message)
      end)

      it("changes on plugin DELETE", function()
        local msg_before = assert_admin_2_wait({
          method = "GET",
          path = "/cache/plugins_iterator:version",
        }, 200)

        local admin_res_plugin = assert(admin_client_1:send {
          method = "DELETE",
          path   = "/plugins/" .. service_plugin_id,
        })
        assert.res_status(204, admin_res_plugin)

        -- the version has changed
        assert_admin_2_wait({
          method = "GET",
          path = "/cache/plugins_iterator:version",
        }, 200, msg_before.message)
      end)

      it("changes on plugin PUT", function()
        local msg_before = assert_admin_2_wait({
          method = "GET",
          path = "/cache/plugins_iterator:version",
        }, 200)

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

        -- the version has changed
        assert_admin_2_wait({
          method = "GET",
          path = "/cache/plugins_iterator:version",
        }, 200, msg_before.message)
      end)
    end)
  end)
end
