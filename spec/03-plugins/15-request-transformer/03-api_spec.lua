local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Plugin: request-transformer (API)", function()
  local admin_client

  teardown(function()
    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  describe("POST", function()
    setup(function()
      helpers.run_migrations()

      assert(helpers.dao.apis:insert {
        name = "test",
        hosts = { "test1.com" },
        upstream_url = "http://mockbin.com"
      })

      assert(helpers.start_kong())
      admin_client = helpers.admin_client()
    end)

    describe("validate config parameters", function()
      it("remove succeeds without colons", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "request-transformer",
            config = {
              remove = {
                headers = "just_a_key",
                body = "just_a_key",
                querystring = "just_a_key",
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
        assert.equals("just_a_key", body.config.remove.body[1])
        assert.equals("just_a_key", body.config.remove.querystring[1])
      end)
      it("add fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "request-transformer",
            config = {
              add = {
                headers = "just_a_key",
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same({ ["config.add.headers"] = "key 'just_a_key' has no value" }, json)
      end)
      it("replace fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "request-transformer",
            config = {
              replace = {
                headers = "just_a_key",
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same({ ["config.replace.headers"]  = "key 'just_a_key' has no value" }, json)
      end)
      it("append fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "request-transformer",
            config = {
              append = {
                headers = "just_a_key",
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        assert.same({ ["config.append.headers"]  = "key 'just_a_key' has no value" }, json)
      end)
    end)
  end)
end)
