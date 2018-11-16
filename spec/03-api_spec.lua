local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-transformer-advanced (API) [#" .. strategy .. "]", function()
    local admin_client

    teardown(function()
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    describe("POST", function()
      setup(function()
        helpers.get_db_utils(strategy)

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        admin_client = helpers.admin_client()
      end)

      describe("validate config parameters", function()
        it("remove succeeds without colons", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer-advanced",
              config = {
                remove = {
                  headers = "just_a_key",
                  json    = "just_a_key",
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
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer-advanced",
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
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer-advanced",
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
          assert.same({ ["config.replace.headers"] = "key 'just_a_key' has no value" }, json)
        end)
        it("append fails with missing colons for key/value separation", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer-advanced",
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
          assert.same({ ["config.append.headers"] = "key 'just_a_key' has no value" }, json)
        end)
      end)
    end)
  end)
end
