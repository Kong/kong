local helpers = require "spec.helpers"


for _, strategy in helpers.all_strategies() do
describe("Status API - with strategy #" .. strategy, function()
  local client
  local admin_client

  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      status_listen = "127.0.0.1:9500",
      plugins = "admin-api-method",
      database = strategy,
    })
    client = helpers.http_client("127.0.0.1", 9500, 20000)

    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)
 
  describe("status readiness endpoint", function()
    it("should return 503 when no config, return 200 in db mode", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/ready"
      })

      if strategy == "off" then
        assert.res_status(503, res)
      else
        assert.res_status(200, res)
      end

    end)

    if strategy == "off" then
      it("should return 503 when no config, and return 200 after a valid config is uploaded", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/ready"
        })

        assert.res_status(503, res)

        local res = assert(admin_client:send {
          method = "POST",
          path = "/config",
          body = {
            config = [[
              _format_version: "3.0"
              services:
              - name: test
                url: http://mockbin.org
            ]]
          },
          headers = {
            ["Content-Type"] = "multipart/form-data"
          }
        })
        assert.res_status(201, res)

        local res = assert(client:send {
          method = "GET",
          path = "/status/ready"
        })
        assert.res_status(200, res)
      end)
    end

    it("should return 200 after loading an invalid config following a previously uploaded valid config.", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/ready"
      })

      assert.res_status(200, res)

      local res = assert(admin_client:send {
        method = "POST",
        path = "/config",
        body = {
          config = [[
            _format"\!@#$
          ]]
        },
        headers = {
          ["Content-Type"] = "multipart/form-data"
        }
      })
      assert.res_status(400, res)

      local res = assert(client:send {
        method = "GET",
        path = "/status/ready"
      })
      assert.res_status(200, res)
    end)
  end)

end)
end
