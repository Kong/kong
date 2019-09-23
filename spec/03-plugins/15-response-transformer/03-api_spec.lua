local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-transformer (API) [#" .. strategy .. "]", function()
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
          "plugins"
        })

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
              name   = "response-transformer",
              config = {
                remove = {
                  headers = { "just_a_key" },
                  json    = { "just_a_key" },
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

          admin_client:send {
            method  = "DELETE",
            path    = "/plugins/" .. body.id,
          }
        end)
        it("rename succeeds with colons", function()
          local rename_header = "x-request-id:x-custom-request-id"
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer",
              config = {
                rename = {
                  headers = { rename_header },
                },
              },
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          assert.response(res).has.status(201)
          local body = assert.response(res).has.jsonbody()
          assert.equals(rename_header, body.config.rename.headers[1])

          admin_client:send {
            method  = "DELETE",
            path    = "/plugins/" .. body.id,
          }
        end)
        it("rename fails with missing colons for header old_name/new_name separation", function()
          local no_colons_header = "x-request-idx-custom-request-id"
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer",
              config = {
                rename = {
                  headers = { no_colons_header },
                },
              },
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          local body = assert.response(res).has.status(400)
          local json = cjson.decode(body)
          assert.same("schema violation", json.name)
          assert.same({ "invalid value: " .. no_colons_header }, json.fields.config.rename.headers)
        end)
        it("rename fails with invalid header name for old_name or new_name separation", function()
          local invalid_header = "x-requ,est-id"
          local rename_header = invalid_header .. ":x-custom-request-id"
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer",
              config = {
                rename = {
                  headers = { rename_header },
                },
              },
            },
            headers = {
              ["Content-Type"] = "application/json",
            },
          })
          local body = assert.response(res).has.status(400)
          local json = cjson.decode(body)
          assert.same("schema violation", json.name)
          assert.same({ "'" .. invalid_header .. "' is not a valid header" }, json.fields.config.rename.headers)
        end)
        it("add fails with missing colons for key/value separation", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer",
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
          assert.same("schema violation", json.name)
          assert.same({ "invalid value: just_a_key" }, json.fields.config.add.headers)
        end)
        it("replace fails with missing colons for key/value separation", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer",
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
          assert.same("schema violation", json.name)
          assert.same({ "invalid value: just_a_key" }, json.fields.config.replace.headers)
        end)
        it("append fails with missing colons for key/value separation", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name   = "response-transformer",
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
          assert.same("schema violation", json.name)
          assert.same({ "invalid value: just_a_key" }, json.fields.config.append.headers)
        end)
      end)
    end)
  end)
end
