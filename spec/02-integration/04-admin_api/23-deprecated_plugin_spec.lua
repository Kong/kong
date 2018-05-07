local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Deprecated plugin API" , function()
  local client

  describe("deprecated not enabled plugins" , function()
    setup(function()
      assert(helpers.dao:run_migrations())
      assert(helpers.start_kong())
      client = helpers.admin_client()
    end)
    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
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
        assert.is_equal("plugin 'admin-api-post-process' not enabled; add it to the 'custom_plugins' configuration property", json.config)
      end)
    end)
  end)

  describe("deprecated enabled plugins" , function()
    setup(function()
      assert(helpers.start_kong({
        custom_plugins = "admin-api-post-process"
      }))
      client = helpers.admin_client()
    end)
    teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
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
