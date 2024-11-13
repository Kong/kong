local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("Admin API - workspaces #" .. strategy, function()
    local db, admin_client

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy,{ "workspaces" })

      assert(helpers.start_kong({
        database = strategy,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if admin_client then admin_client:close() end
    end)

    it("has no admin api", function()
      finally(function() db:truncate("workspaces") end)

      local res = assert(admin_client:post("/workspaces", {
        body = { name = "jim" },
        headers = {["Content-Type"] = "application/json"},
      }))

      local body = assert.res_status(404, res)
      body = cjson.decode(body)
      assert.match("Not found", body.message)
    end)

    it("disallow deletion", function()
      finally(function() db:truncate("workspaces") end)

      local res = assert(admin_client:delete("/workspaces/default"))
      local body = assert.res_status(404, res)
      body = cjson.decode(body)
      assert.match("Not found", body.message)
    end)
  end)
end
