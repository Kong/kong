local State = require "kong.db.migrations.state"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("db.migrations.State", function()
    describe("load", function()
      it("loads subsystems in alphabetical order", function()
        local _, db = helpers.get_db_utils(strategy)
        local state = State.load(db)

        local namespaces = {}
        local sorted_namespaces = {}
        for i, subsystem in ipairs(state.executed_migrations) do
          namespaces[i] = subsystem.namespace
          sorted_namespaces[i] = subsystem.namespace
        end
        table.sort(sorted_namespaces)

        assert.same(namespaces, sorted_namespaces)
      end)
    end)

    describe("is_migration_executed", function()
      local db
      local state
      before_each(function()
        _, db = helpers.get_db_utils(strategy)
        state = State.load(db)
      end)

      it("false on non-existing subsystems or migrations, true on existing ones", function()
        assert.is_falsy(state:is_migration_executed("foo", "bar"))
        assert.is_falsy(state:is_migration_executed("core", "foo"))
      end)

      it("succeeds on executed subsystems + migrations", function()
        assert.is_truthy(state:is_migration_executed("core", "000_base"))
      end)
    end)
  end)
end
