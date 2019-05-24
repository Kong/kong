local helpers = require "spec.helpers"
local pl_path = require "pl.path"
local pl_file = require "pl.file"


local FILE_LOG_PATH = os.tmpname()
local POLL_INTERVAL = 0.3


local MOCK_SERIALIZER_FOO = [[
return {
  serialize = function(ngx)
    return "all your base"
  end
}
]]
local MOCK_SERIALIZER_BAR = [[
return {
  serialize = function(ngx)
    return "belong to them"
  end
}
]]


for _, strategy in helpers.each_strategy() do
  describe("log serializers invalidations with db [#" .. strategy .. "]", function()

    local admin_client_1

    local proxy_client_1
    local proxy_client_2

    local wait_for_propagation

    local service_fixture, log_serializer_fixture

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "log_serializers",
        "plugins",
        "routes",
        "services",
      })

      service_fixture = bp.services:insert()
      bp.routes:insert {
        protocols = { "http" },
        hosts = { "mock_upstream" },
        service = service_fixture,
      }
      log_serializer_fixture = bp.log_serializers:insert {
        chunk = ngx.encode_base64(MOCK_SERIALIZER_FOO)
      }
      bp.plugins:insert {
        name = "file-log",
        service = { id = service_fixture.id },
        config = {
          path = FILE_LOG_PATH,
          serializer = { id = log_serializer_fixture.id },
        }
      }

      local db_update_propagation = strategy == "cassandra" and 0.1 or 0

      os.remove(FILE_LOG_PATH)
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

      wait_for_propagation = function()
        ngx.sleep(POLL_INTERVAL * 2 + db_update_propagation * 2)
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot1", true)
      helpers.stop_kong("servroot2", true)
    end)

    before_each(function()
      admin_client_1 = helpers.http_client("127.0.0.1", 8001)
      proxy_client_1 = helpers.http_client("127.0.0.1", 8000)
      proxy_client_2 = helpers.http_client("127.0.0.1", 9000)
    end)

    after_each(function()
      admin_client_1:close()
      proxy_client_1:close()
      proxy_client_2:close()
    end)

    describe("broadcasts", function()
      it("uses the first serializer", function()
        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            Host = "mock_upstream",
          }
        })
        assert.res_status(200, res_1)

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            Host = "mock_upstream",
          }
        })
        assert.res_status(200, res_2)

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 10)

        local log = pl_file.read(FILE_LOG_PATH)

        for s in log:gmatch("[^\r\n]+") do
          assert.same("\"all your base\"", s)
        end
      end)

      it("updates the serializer chunk", function()
        local admin_res = assert(admin_client_1:send {
          method  = "PATCH",
          path    = "/log_serializers/" .. log_serializer_fixture.id,
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            chunk = ngx.encode_base64(MOCK_SERIALIZER_BAR),
          },
        })
        assert.res_status(200, admin_res)

        wait_for_propagation()

        local res_1 = assert(proxy_client_1:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            Host = "mock_upstream",
          }
        })
        assert.res_status(200, res_1)

        local res_2 = assert(proxy_client_2:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            Host = "mock_upstream",
          }
        })
        assert.res_status(200, res_2)

        helpers.wait_until(function()
          return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
        end, 10)

        local log = pl_file.read(FILE_LOG_PATH)

        local i = 0
        for s in log:gmatch("[^\r\n]+") do
          i = i + 1

          if i > 2 then
            assert.same("\"belong to them\"", s)
          end
        end
      end)
    end)
  end)
end
