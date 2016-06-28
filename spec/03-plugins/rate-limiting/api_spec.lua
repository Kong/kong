local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Rate Limiting API", function()
  local admin_client
  setup(function()
    helpers.kill_all()
    assert(helpers.prepare_prefix())
    assert(helpers.start_kong())
    admin_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)
  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("POST", function()
    setup(function()
      assert(helpers.dao.apis:insert {
        name = "test",
        request_host = "test1.com",
        upstream_url = "http://mockbin.com"
      })
    end)

    it("should not save with empty config", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/test/plugins/",
        body = {
          name = "rate-limiting"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      assert.equal([[{"config":"You need to set at least one limit: second, minute, hour, day, month, year"}]], body)
    end)

    it("should save with proper config", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/test/plugins/",
        body = {
          name = "rate-limiting",
          config = {
            second = 10
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(201, res))
      assert.equal(10, body.config.second)
    end)
  end)
end)
