local helpers = require "spec.helpers"
local scope = require "kong.enterprise_edition.workspaces.scope"


for _, strategy in helpers.each_strategy() do
  local bp, db

  describe("cascade delete workspace entities [#" .. strategy .. "]", function()
    setup(function()
      bp, db = helpers.get_db_utils(strategy)
    end)

    it(":delete", function()
      db:truncate("consumers")
      db:truncate("workspaces")

      local w1 = assert(bp.workspaces:insert({ name = "w1" }))
      local c1 = assert(bp.consumers:insert_ws({ username = "c1" }, w1))
      assert(bp.basicauth_credentials:insert_ws({
        username = "gruce",
        password = "ovo",
        consumer = { id = c1.id },
      }, w1))

      assert(scope.run_with_ws_scope({ w1 }, function()
        return db.consumers:delete({ id = c1.id })
      end))
    end)

    it(":delete_by", function()
      db:truncate("consumers")
      db:truncate("workspaces")

      local w1 = assert(bp.workspaces:insert({ name = "w1" }))
      local c1 = assert(bp.consumers:insert_ws({ username = "c1" }, w1))
      assert(bp.basicauth_credentials:insert_ws({
        username = "gruce",
        password = "ovo",
        consumer = { id = c1.id },
      }, w1))

      assert(scope.run_with_ws_scope({ w1 }, function()
        return db.consumers:delete_by_username(c1.username)
      end))
    end)
  end)
end
