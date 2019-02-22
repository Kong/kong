local helpers = require "spec.helpers"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"


for _, strategy in helpers.each_strategy() do

describe("Workspaces helpers", function()
  local db

  setup(function()
    _, db, _ = helpers.get_db_utils(strategy)
    singletons.db = db
  end)

  describe("upsert_default", function()
    it("returns existing default workspace", function()
      local ws1, ws2, err

      ws1, err = workspaces.upsert_default(db)
      assert.is_nil(err)
      assert.not_nil(ws1)
      assert.same("default", ws1.name)

      db:truncate() -- recreates default workspace

      ws2, err = db.workspaces:select_by_name("default")
      assert.is_nil(err)
      assert.not_nil(ws2)
      assert.same("default", ws2.name)

      assert.not_same(ws1.id, ws2.id)
    end)

    it("is called by db:truncate", function()
      local s = spy.new(workspaces.upsert_default)
      workspaces.upsert_default = s

      assert.spy(s).was.called(0)
      db:truncate("services") -- not called on services truncate
      assert.spy(s).was.called(0)
      db:truncate("workspaces") -- called on workspaces truncate
      assert.spy(s).was.called(1)
      db:truncate("plugins") -- not called on plugins truncate
      assert.spy(s).was.called(1)
      db:truncate() -- called on global truncate
      assert.spy(s).was.called(2)
    end)
  end)
end)

end
