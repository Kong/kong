local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("rate-limiting API", function()
  local admin_client

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
        hosts = { "test1.com" },
        upstream_url = "http://mockbin.com"
      })

      assert(helpers.start_kong())
      admin_client = helpers.admin_client()
    end)

    it("errors with size/limit mismatch", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/test/plugins/",
        body = {
          name = "rate-limiting",
          config = {
            window_size = { 10, 60 },
            limit = { 10 },
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same({
        config = "You must provide the same number of windows and limits",
      }, body)
    end)

    it("errors with missing size/limit configs", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/apis/test/plugins/",
        body = {
          name = "rate-limiting",
          config = {
            limit = { 10 },
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same({
        ["config.window_size"] = "window_size is required",
      }, body)
    end)
  end)
end)
