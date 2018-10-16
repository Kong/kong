local helpers = require "spec.helpers"
local Errors = require "kong.db.errors"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do

describe("Deprecated plugin API #" .. strategy, function()
  local client
  local db

  describe("deprecated not enabled plugins" , function()
    setup(function()
      local _
      _, db = helpers.get_db_utils(strategy, {
        "plugins",
      }, {
        "admin-api-post-process"
      })
      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
      client = helpers.admin_client()
    end)

    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      db.plugins:truncate()
    end)

    describe("POST" , function()
      it("returns 400 on non enabled plugin" , function()
        local res = assert(client:send {
          method = "POST",
          path = "/plugins/",
          body = {
            name = "admin-api-post-process"
          },
          headers = { ["Content-Type"] = "application/json" }
        })
        local body = assert.res_status(400 , res)
        local json = cjson.decode(body)
        assert.same({
          code = Errors.codes.SCHEMA_VIOLATION,
          fields = {
            name = "plugin 'admin-api-post-process' not enabled; add it to the 'plugins' configuration property"
          },
          message = "schema violation (name: plugin 'admin-api-post-process' not enabled; add it to the 'plugins' configuration property)",
          name = "schema violation",
        }, json)
      end)
    end)
  end)

  describe("deprecated enabled plugins" , function()
    setup(function()
      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled, admin-api-post-process"
      }))
      client = helpers.admin_client()
    end)
    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      db.plugins:truncate()
    end)

    describe("GET" , function()
      it("returns 201 for enabled plugin" , function()
        local res = assert(client:send {
          method = "POST",
          path = "/plugins/",
          body = {
            name = "admin-api-post-process"
          },
          headers = { ["Content-Type"] = "application/json" }
        })
        assert.res_status(201 , res)
      end)
    end)
  end)
end)

end
