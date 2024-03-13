local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("Admin API - DNS client route with [#" .. strategy .. "]" , function()
    local client

    lazy_setup(function()
      helpers.get_db_utils(strategy)

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
    end)

    it("/dns", function ()
      local res = assert(client:send {
        method = "GET",
        path = "/dns",
        headers = { ["Content-Type"] = "application/json" }
      })

      local body = assert.res_status(200 , res)
      local json = cjson.decode(body)

      assert(type(json.worker.id) == "number")
      assert(type(json.worker.count) == "number")

      assert(type(json.stats) == "table")
      assert(type(json.stats["127.0.0.1"].runs) == "number")
    end)
  end)
end
