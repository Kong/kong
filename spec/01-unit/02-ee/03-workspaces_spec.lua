local workspaces = require "kong.workspaces"

describe("workspaces", function()
  local workspaceable_relations = workspaces.get_workspaceable_relations()
  describe("workspaceable relations", function()
    it("is a table", function()
      assert.is_table(workspaceable_relations)
    end)
    it("is immutable", function()
      local ok, err = pcall(function()
        workspaceable_relations.newfield = 123
      end)
      assert.falsy(ok)
      assert.matches("immutable table", err)
    end)
    it("can be added", function()
      assert.is_true(workspaces.register_workspaceable_relation("rel1", {"id1"}))
      assert.is_true(workspaces.register_workspaceable_relation("rel2", {"id2"}))
      assert.equal(workspaceable_relations.rel1, "id1")
      assert.equal(workspaceable_relations.rel2, "id2")
    end)
    it("iterates", function()
      local items = {rel1 = "id1", rel2 = "id2"}
      for k, v in pairs(workspaceable_relations) do
        assert.equals(v, items[k])
      end
    end)
    it("has a protected metatable", function()
      local ok = pcall(getmetatable, workspaceable_relations)
      assert.is_true(ok)
    end)
  end)
end)
