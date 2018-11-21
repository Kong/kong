local cjson = require "cjson"
local helpers = require "spec.helpers"

describe("Plugin: rate-limiting (API)", function()
  local admin_client
  local dao

  lazy_setup(function()
    dao = select(3, helpers.get_db_utils())
  end)

  lazy_teardown(function()
    if admin_client then admin_client:close() end
    helpers.stop_kong()
  end)

  describe("POST", function()
    lazy_setup(function()

      assert(dao.apis:insert {
        name         = "test",
        hosts        = { "test1.com" },
        upstream_url = helpers.mock_upstream_url,
      })

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
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
      local json = cjson.decode(body)
      assert.same([[at least one of these fields must be non-empty: ]] ..
                  [['config.second', 'config.minute', 'config.hour', ]] ..
                  [['config.day', 'config.month', 'config.year']],
                  json.fields["@entity"][1])
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
