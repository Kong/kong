local spec_helper = require "spec.spec_helpers"
local Migrations = require "kong.tools.migrations"
local utils = require "kong.tools.utils"
local path = require("path").new("/")

describe("Migrations #tools", function()

  local migrations

  before_each(function()
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

  for db_type, v in pairs(spec_helper.configuration.databases_available) do

    local files = {}
    local migration_path = path:join("./database/migrations", db_type)
    local fixture_path = path:join(migration_path, "2015-12-12-000000_test_migration.lua")
    local fixture_migration = [[
      return {
        name = "2015-12-12-000000_test_migration",
        up = function(options) return "" end,
        down = function(options) return "" end
      }
    ]]

    setup(function()
      utils.write_to_file(fixture_path, fixture_migration)
      local mig_files = utils.retrieve_files(migration_path, '.lua')
      for _, mig in ipairs(mig_files) do
        table.insert(files, mig.name)
      end
    end)

    teardown(function()
      os.remove(fixture_path)
    end)

    before_each(function()
      stub(spec_helper.dao_factory, "execute_queries")
      stub(spec_helper.dao_factory, "delete_migration")
      stub(spec_helper.dao_factory, "add_migration")
    end)

    describe(db_type.." #migrate()", function()

      it("1st run should execute all created migrations in order for a given dao", function()
        spec_helper.dao_factory.get_migrations = spy.new(function() return nil end)

        local i = 0
        migrations:migrate(function(migration, err)
          assert.truthy(migration)
          assert.are.same(files[i+1], migration.name..".lua")
          assert.falsy(err)
          i = i + 1
        end)

        assert.are.same(#files, i)

        -- all migrations should be recorded in db
        assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
        assert.spy(spec_helper.dao_factory.execute_queries).was.called(#files)
        assert.spy(spec_helper.dao_factory.add_migration).was.called(#files)
      end)

      describe("Partly already migrated", function()

        it("if running with some migrations pending, it should only execute the non-recorded ones", function()
          spec_helper.dao_factory.get_migrations = spy.new(function() return {files[1]} end)

          local i = 0
          migrations:migrate(function(migration, err)
            assert.truthy(migration)
            assert.are.same("2015-12-12-000000_test_migration", migration.name)
            assert.falsy(err)
            i = i + 1
          end)

          assert.are.same(1, i)
          assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
          assert.spy(spec_helper.dao_factory.execute_queries).was.called(1)
          assert.spy(spec_helper.dao_factory.add_migration).was.called(1)
        end)
      end)

    end)

    describe("Already migrated", function()

      it("if running again, should detect if migrations are already up to date", function()
        spec_helper.dao_factory.get_migrations = spy.new(function() return files end)

        local i = 0
        migrations:migrate(function(migration, err)
          assert.falsy(migration)
          assert.falsy(err)
          i = i + 1
        end)

        assert.are.same(1, i)
        assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
        assert.spy(spec_helper.dao_factory.execute_queries).was_not_called()
        assert.spy(spec_helper.dao_factory.add_migration).was_not_called()
      end)
    end)

    it("should report get_migrations errors", function()
      spec_helper.dao_factory.get_migrations = spy.new(function()
                                                return nil, "get err"
                                              end)
      local i = 0
      migrations:migrate(function(migration, err)
        assert.falsy(migration)
        assert.truthy(err)
        assert.are.same("get err", err)
        i = i + 1
      end)

      assert.are.same(1, i)
      assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
      assert.spy(spec_helper.dao_factory.execute_queries).was_not_called()
      assert.spy(spec_helper.dao_factory.add_migration).was_not_called()
    end)

    it("should report execute_queries errors", function()
      spec_helper.dao_factory.get_migrations = spy.new(function() return {} end)
      spec_helper.dao_factory.execute_queries = spy.new(function()
                                                return "execute error"
                                              end)
      local i = 0
      migrations:migrate(function(migration, err)
        assert.falsy(migration)
        assert.truthy(err)
        assert.are.same("execute error", err)
        i = i + 1
      end)

      assert.are.same(1, i)
      assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
      assert.spy(spec_helper.dao_factory.execute_queries).was.called(1)
      assert.spy(spec_helper.dao_factory.add_migration).was_not_called()
    end)

    it("should report add_migrations errors", function()
      spec_helper.dao_factory.get_migrations = spy.new(function() return {} end)
      spec_helper.dao_factory.add_migration = spy.new(function()
                                                return nil, "add error"
                                              end)
      local i = 0
      migrations:migrate(function(migration, err)
        assert.truthy(migration)
        assert.truthy(err)
        assert.are.same("Cannot record migration "..migration.name..": add error", err)
        i = i + 1
      end)

      assert.are.same(1, i)
      assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
      assert.spy(spec_helper.dao_factory.execute_queries).was.called(1)
      assert.spy(spec_helper.dao_factory.add_migration).was.called(1)
    end)

    describe(db_type.." #rollback()", function()

      local old_migrations = {}

      setup(function()
        for _, f_name in ipairs(files) do
          table.insert(old_migrations, f_name:sub(0, -5))
        end
      end)

      describe("rollback latest migration", function()

        it("should only rollback the latest executed migration", function()
          spec_helper.dao_factory.get_migrations = spy.new(function() return old_migrations end)

          local i = 0
          migrations:rollback(function(migration, err)
            assert.truthy(migration)
            assert.are.same(old_migrations[#old_migrations], migration.name)
            assert.falsy(err)
            i = i + 1
          end)

          assert.are.same(1, i)
          assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
          assert.spy(spec_helper.dao_factory.execute_queries).was.called(1)
          assert.spy(spec_helper.dao_factory.delete_migration).was.called(1)
        end)

      end)

      it("should not call delete_migration if init migration is rollbacked", function()
        spec_helper.dao_factory.get_migrations = spy.new(function() return {old_migrations[1]} end)

        local i = 0
        migrations:rollback(function(migration, err)
          assert.truthy(migration)
          assert.are.same(old_migrations[1], migration.name)
          assert.falsy(err)
          i = i + 1
        end)

        assert.are.same(1, i)
        assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
        assert.spy(spec_helper.dao_factory.execute_queries).was.called(1)
        assert.spy(spec_helper.dao_factory.delete_migration).was_not_called()
      end)

      it("should report get_migrations errors", function()
        spec_helper.dao_factory.get_migrations = spy.new(function()
                                                  return nil, "get err"
                                                end)
        local i = 0
        migrations:rollback(function(migration, err)
          assert.falsy(migration)
          assert.truthy(err)
          assert.are.same("get err", err)
          i = i + 1
        end)

        assert.are.same(1, i)
        assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
        assert.spy(spec_helper.dao_factory.execute_queries).was_not_called()
        assert.spy(spec_helper.dao_factory.delete_migration).was_not_called()
      end)

      it("should report execute_queries errors", function()
        spec_helper.dao_factory.get_migrations = spy.new(function() return old_migrations end)
        spec_helper.dao_factory.execute_queries = spy.new(function()
                                                  return "execute error"
                                                end)
        local i = 0
        migrations:rollback(function(migration, err)
          assert.falsy(migration)
          assert.truthy(err)
          assert.are.same("execute error", err)
          i = i + 1
        end)

        assert.are.same(1, i)
        assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
        assert.spy(spec_helper.dao_factory.execute_queries).was.called(1)
        assert.spy(spec_helper.dao_factory.delete_migration).was_not_called()
      end)

      it("should report delete_migrations errors", function()
        spec_helper.dao_factory.get_migrations = spy.new(function() return old_migrations end)
        spec_helper.dao_factory.delete_migration = spy.new(function()
                                                    return nil, "delete error"
                                                  end)
        local i = 0
        migrations:rollback(function(migration, err)
          assert.truthy(migration)
          assert.truthy(err)
          assert.are.same("Cannot delete migration "..migration.name..": delete error", err)
          i = i + 1
        end)

        assert.are.same(1, i)
        assert.spy(spec_helper.dao_factory.get_migrations).was.called(1)
        assert.spy(spec_helper.dao_factory.execute_queries).was.called(1)
        assert.spy(spec_helper.dao_factory.delete_migration).was.called(1)
      end)

    end)

    describe(db_type.." #reset()", function()

      local old_migrations = {}

      setup(function()
        for _, f_name in ipairs(files) do
          table.insert(old_migrations, f_name:sub(0, -5))
        end
      end)

      it("should rollback all migrations at once", function()
        local i = 0
        local expected_rollbacks = #old_migrations
        spec_helper.dao_factory.get_migrations = spy.new(function()
                                                          return old_migrations
                                                        end)
        migrations:reset(function(migration, err)
          assert.falsy(err)
          if i < expected_rollbacks then
            assert.are.same(old_migrations[#old_migrations], migration.name)
            table.remove(old_migrations, #old_migrations)
          else
            -- Last call to cb when all migrations are done
            assert.falsy(migration)
            assert.falsy(err)
          end
          i = i + 1
        end)

        assert.are.same(expected_rollbacks + 1, i)
        assert.spy(spec_helper.dao_factory.get_migrations).was.called(expected_rollbacks + 1) -- becaue also run one last time to check if any more migrations
        assert.spy(spec_helper.dao_factory.execute_queries).was.called(expected_rollbacks)
        assert.spy(spec_helper.dao_factory.delete_migration).was.called(expected_rollbacks - 1) -- because doesn't run for ini migration
      end)

    end)
  end
end)
