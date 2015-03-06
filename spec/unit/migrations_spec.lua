local spec_helper = require "spec.spec_helpers"
local Migrations = require "kong.tools.migrations"
local utils = require "kong.tools.utils"

describe("Migrations #tools", function()

  local migrations

  setup(function()
    migrations = Migrations(spec_helper.dao_factory)
  end)

  it("first migration should have an init boolean property", function()
    -- `init` says to the migrations not to record changes in db for this migration
  end)

  describe("#create()", function()

    it("should create an empty migration interface for each available dao", function()
      local n_databases_available = utils.table_size(spec_helper.configuration.databases_available)

      local s_cb = spy.new(function(interface, f_path, f_name, dao_type)
        assert.are.same("string", type(interface))
        assert.are.same("./database/migrations/"..dao_type, f_path)
        assert.are.same(os.date("%Y-%m-%d-%H%M%S").."_".."test_migration", f_name)

        local mig_module = loadstring(interface)()
        assert.are.same("function", type(mig_module.up))
        assert.are.same("function", type(mig_module.down))
        assert.are.same(f_name, mig_module.name)
      end)

      migrations.create(spec_helper.configuration, "test_migration", s_cb)

      assert.spy(s_cb).was.called(n_databases_available)
    end)

  end)

  describe("#migrate()", function()

    it("should execute all created migrations in order", function()

    end)

    it("should record all executed migrations in DB", function()

    end)

    it("if running again, should detect if migrations are already up to date", function()

    end)

  end)

  describe("#rollback()", function()

    it("should rollback the latest executed migration", function()

    end)

    it("if running again, should detect if migrations are already all reverted", function()

    end)

  end)

  describe("#reset()", function()

    it("should rollback all migrations at once", function()

    end)

  end)
end)
