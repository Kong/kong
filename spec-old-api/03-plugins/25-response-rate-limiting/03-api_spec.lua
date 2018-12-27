local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: response-rate-limiting (API)", function()
  local admin_client

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("POST", function()
    lazy_setup(function()
      helpers.dao.apis:truncate()
      helpers.db.plugins:truncate()
      assert(helpers.dao.apis:insert {
        name         = "test",
        hosts        = { "test1.com" },
        upstream_url = helpers.mock_upstream_url,
      })

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
    end)

    it("errors on empty config", function()
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
      local json = cjson.decode(body)
      assert.same("required field missing", json.fields.config.limits)
    end)
    it("accepts proper config", function()
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
