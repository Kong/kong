-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local State = require "kong.db.migrations.state"
local helpers = require "spec.helpers"

local function sort_migration_ns(a, b)
  local mod_pattern = "^kong%.(.*)%.migrations"
  local a_mod = a:match(mod_pattern)
  local b_mod = b:match(mod_pattern)

  assert.is_string(a_mod)
  assert.is_string(b_mod)

  return a_mod < b_mod
end

for _, strategy in helpers.each_strategy() do
  describe("db.migrations.State", function()
    describe("load", function()
      it("loads subsystems in alphabetical order", function()
        --[[ XXX: EE
          This test has been modified to incorporate the enterprise subsystem.
          Core plugins with enterprise migrations need to run after base
          enterprise migrations have been executed:

            1. Core base migrations
            2. Core ordered plugin migrations
            3. Enterprise base migrations
            4. Core ordered plugin enterprise migrations

          The reason for this is some core plugin enterprise migrations inspect
          values from enterprise base tables that are not present in the core
          base tables.
        -- EE ]]
        local _, db = helpers.get_db_utils(strategy)
        local state = State.load(db)

        local namespaces = {}
        local enterprise_namespaces = {}
        local sorted_namespaces = {}
        local sorted_enterprise_namespaces = {}
        for _, subsystem in ipairs(state.executed_migrations) do
          if subsystem.namespace:find("enterprise") then
            enterprise_namespaces[#enterprise_namespaces + 1] = subsystem.namespace
            sorted_enterprise_namespaces[#sorted_enterprise_namespaces + 1] = subsystem.namespace
          else
            namespaces[#namespaces + 1] = subsystem.namespace
            sorted_namespaces[#sorted_namespaces + 1] = subsystem.namespace
          end
        end

        table.sort(sorted_namespaces, sort_migration_ns)
        table.sort(sorted_enterprise_namespaces, sort_migration_ns)

        assert.same(namespaces, sorted_namespaces)
        assert.same(enterprise_namespaces, sorted_enterprise_namespaces)
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
