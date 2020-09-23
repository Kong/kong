local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("default workspace after migrations [#" .. strategy .. "]", function()
    it("is contains the correct defaults", function()
      local _, db
      _, db = helpers.get_db_utils(strategy, { "workspaces" })
      local default_ws = assert(db.workspaces:select_by_name("default"))
      assert.equal("default", default_ws.name)
      assert.same({}, default_ws.meta)
      assert.is_not_nil(default_ws.created_at)
      assert.equal(false , default_ws.config.portal)
    end)
  end)
end
