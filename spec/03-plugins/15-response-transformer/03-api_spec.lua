local helpers = require "spec.helpers"

describe("Plugin: response-transformer (API)", function()
  local admin_client
  setup(function()
    assert(helpers.start_kong())
    admin_client = helpers.admin_client()
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

    describe("validate config parameters", function()
      it("remove succeeds without colons", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "response-transformer",
            config = {
              remove = {
                headers = "just_a_key",
                json = "just_a_key",
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
                headers = "just_a_key",
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        assert.equals([[{"config.add.headers":"key 'just_a_key' has no value"}]], body)
      end)
      it("replace fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "response-transformer",
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
        assert.equals([[{"config.replace.headers":"key 'just_a_key' has no value"}]], body)
      end)
      it("append fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/apis/test/plugins/",
          body = {
            name = "response-transformer",
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
        assert.equals([[{"config.append.headers":"key 'just_a_key' has no value"}]], body)
      end)
    end)
  end)
end)
