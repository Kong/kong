local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
describe("Plugin: request-transformer (API) [#" .. strategy .. "]", function()
  local admin_client

  lazy_teardown(function()
    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  describe("POST", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "plugins",
      })

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = "bundled, request-transformer",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      admin_client = helpers.admin_client()
    end)

    describe("validate config parameters", function()
      it("remove succeeds without colons", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/plugins",
          body = {
            name = "request-transformer",
            config = {
              remove = {
                headers = {"just_a_key"},
                body = {"just_a_key"},
                querystring = {"just_a_key"},
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
          path = "/plugins",
          body = {
            name = "request-transformer",
            config = {
              add = {
                headers = {"just_a_key"},
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        local msg = { "invalid value: just_a_key" }
        local expected = { config = { add = { headers = msg } } }
        assert.same(expected, json["fields"])
      end)
      it("replace fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/plugins",
          body = {
            name = "request-transformer",
            config = {
              replace = {
                headers = {"just_a_key"},
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        local msg = { "invalid value: just_a_key" }
        local expected = { config = { replace = { headers = msg } } }
        assert.same(expected, json["fields"])
      end)
      it("append fails with missing colons for key/value separation", function()
        local res = assert(admin_client:send {
          method = "POST",
          path = "/plugins",
          body = {
            name = "request-transformer",
            config = {
              append = {
                headers = {"just_a_key"},
              },
            },
          },
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = assert.response(res).has.status(400)
        local json = cjson.decode(body)
        local msg = { "invalid value: just_a_key" }
        local expected = { config = { append = { headers = msg } } }
        assert.same(expected, json["fields"])
      end)
        it("it does not allow null value for arrays", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "request-transformer",
              config = {
                remove = {
                  body        = cjson.null,
                  headers     = cjson.null,
                  querystring = cjson.null,
                },
                rename = {
                  body        = cjson.null,
                  headers     = cjson.null,
                  querystring = cjson.null,
                },
                replace = {
                  body        = cjson.null,
                  headers     = cjson.null,
                  querystring = cjson.null,
                },
                add = {
                  body        = cjson.null,
                  headers     = cjson.null,
                  querystring = cjson.null,
                },
                append = {
                  body        = cjson.null,
                  headers     = cjson.null,
                  querystring = cjson.null,
                },
              },
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.response(res).has.status(400)
          local body = assert.response(res).has.jsonbody()
          assert.same({
            remove = {
              body        = "required field missing",
              headers     = "required field missing",
              querystring = "required field missing",
            },
            rename = {
              body        = "required field missing",
              headers     = "required field missing",
              querystring = "required field missing",
            },
            replace = {
              body        = "required field missing",
              headers     = "required field missing",
              querystring = "required field missing",
            },
            add = {
              body        = "required field missing",
              headers     = "required field missing",
              querystring = "required field missing",
            },
            append = {
              body        = "required field missing",
              headers     = "required field missing",
              querystring = "required field missing",
            },
          }, body.fields.config)
        end)

    end)
  end)
end)
end
