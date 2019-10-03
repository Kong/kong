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
          plugins = "bundled, response-transformer-advanced",
        }))

        admin_client = helpers.admin_client()
      end)

      describe("validate config parameters", function()
        it("transform accepts a #function that returns a function", function()
          local some_function = [[
            return function ()
              print("hello world")
            end
          ]]
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer-advanced",
              config = {
                transform = {
                  functions = { some_function },
                },
              },
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.response(res).has.status(201)
          local body = assert.response(res).has.jsonbody()
          assert.same({ some_function }, body.config.transform.functions)
        end)
        it("transform fails when #function is not lua code", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer-advanced",
              config = {
                transform = {
                  functions = { [[ all your base are belong to us ]] },
                },
              },
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          local body = assert.response(res).has.status(400)
          local json = cjson.decode(body)
          local msg = json.fields.config.transform.functions[1]
          assert.match("Error parsing function: ", msg)
        end)
        it("transform fails when #function does not return a function", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer-advanced",
              config = {
                transform = {
                  functions = { [[ print("hello world") ]] }
                },
              },
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          local body = assert.response(res).has.status(400)
          local json = cjson.decode(body)
          local msg = "Bad return value from function, expected function type, got string"
          local expected = { config = { transform = { functions = { msg } } } }
          assert.same(expected, json["fields"])
        end)
      end)
    end)
  end)
end
