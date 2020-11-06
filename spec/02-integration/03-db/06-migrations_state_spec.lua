-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local State = require "kong.db.migrations.state"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("db.migrations.State", function()
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
