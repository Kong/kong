local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: response-transformer (API)", function()
  local admin_client

  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong()
  end)

  describe("POST", function()
    setup(function()
      local dao = select(3, helpers.get_db_utils())

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

    describe("validate config parameters", function()
      it("remove succeeds without colons", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "response-transformer",
            config = {
              remove = {
                headers = { "just_a_key" },
                json = { "just_a_key" },
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        assert.response(res).has.status(201)
        local body = assert.response(res).has.jsonbody()
        assert.equals("just_a_key", body.config.remove.headers[1])
        assert.equals("just_a_key", body.config.remove.json[1])
      end)
      it("add fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "response-transformer",
            config = {
              add = {
                headers = { "just_a_key" },
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("invalid value: just_a_key", json.fields.config.add.headers)
      end)
      it("replace fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "response-transformer",
            config = {
              replace = {
                headers = { "just_a_key" },
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("invalid value: just_a_key", json.fields.config.replace.headers)
      end)
      it("append fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "response-transformer",
            config = {
              append = {
                headers = { "just_a_key" },
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same("invalid value: just_a_key", json.fields.config.append.headers)
      end)
    end)
  end)
end)
