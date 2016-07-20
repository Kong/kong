local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: response-rate-limiting (API)", function()
  local admin_client
  setup(function()
    helpers.prepare_prefix()
    assert(helpers.start_kong())

    admin_client = helpers.admin_client()
  end)
  teardown(function()
    if admin_client then
      admin_client:close()
    end
    assert(helpers.stop_kong())
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
          name = "response-ratelimiting"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(400, res)
      assert.equal([[{"config":"You need to set at least one limit name"}]], body)
    end)

    it("should save with proper config", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/test/plugins/",
        body = {
          name = "response-ratelimiting",
          config = {
            limits = {
              video = {second = 10}
            }
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(201, res))
      assert.equal(10, body.config.limits.video.second)
    end)
  end)
end)
