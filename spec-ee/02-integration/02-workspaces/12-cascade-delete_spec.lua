local helpers = require "spec.helpers"
local workspaces = require "kong.workspaces"


for _, strategy in helpers.each_strategy() do
  local bp, db

  describe("cascade delete workspace entities [#" .. strategy .. "]", function()
    setup(function()
      bp, db = helpers.get_db_utils(strategy)
    end)

    it(":delete", function()
      db:truncate("services")
      db:truncate("plugins")
      db:truncate("workspaces")
      db:truncate("workspace_entities")

      local w1 = assert(bp.workspaces:insert({ name = "w1" }))
      local s1 = assert(bp.services:insert_ws({ name = "s1" }, w1))
      assert(bp.plugins:insert_ws({
        name = "key-auth",
        service = {id = s1.id },
      }, w1))

      local ws_entities = db.workspace_entities:select_all()
      assert(#ws_entities > 0)

      assert(workspaces.run_with_ws_scope({ w1 }, function()
        return db.services:delete({ id = s1.id })
      end))

      local ws_entities = db.workspace_entities:select_all()
      assert(#ws_entities == 0)
    end)

    it(":delete_by", function()
      db:truncate("services")
      db:truncate("plugins")
      db:truncate("workspaces")
      db:truncate("workspace_entities")

      local w1 = assert(bp.workspaces:insert({ name = "w1" }))
      local s1 = assert(bp.services:insert_ws({ name = "s1" }, w1))
      assert(bp.plugins:insert_ws({
        name = "key-auth",
        service = { id = s1.id }
      }, w1))

      assert(workspaces.run_with_ws_scope({ w1 }, function()
        return db.services:delete_by_name(s1.name)
      end))

      local ws_entities = db.workspace_entities:select_all()
      assert(#ws_entities == 0, #ws_entities)
    end)
  end)
end
