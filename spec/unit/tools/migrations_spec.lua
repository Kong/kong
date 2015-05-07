local spec_helper = require "spec.spec_helpers"
local Migrations = require "kong.tools.migrations"
local utils = require "kong.tools.utils"
local IO = require "kong.tools.io"

describe("Migrations", function()

  local env = spec_helper.get_env()
  local migrations

  before_each(function()
    migrations = Migrations(env.dao_factory)
  end)

  describe("#create()", function()

    it("should create an empty migration interface for each available dao", function()
      local n_databases_available = utils.table_size(env.configuration.databases_available)

      local s_cb = spy.new(function(interface, f_path, f_name, dao_type)
        assert.are.same("string", type(interface))
        assert.are.same(IO.path:join(migrations.migrations_path, dao_type), f_path)
        assert.are.same(os.date("%Y-%m-%d-%H%M%S").."_".."test_migration", f_name)

        local mig_module = loadstring(interface)()
        assert.are.same("function", type(mig_module.up))
        assert.are.same("function", type(mig_module.down))
        assert.are.same(f_name, mig_module.name)
      end)

      migrations:create(env.configuration, "test_migration", s_cb)

      assert.spy(s_cb).was.called(n_databases_available)
    end)

  end)

  for db_type, v in pairs(env.configuration.databases_available) do

    local migrations_names = {} -- used to mock dao's get_migrations for already executed migrations
    local migrations_path = IO.path:join("./database/migrations", db_type)
    local fixtures_path = IO.path:join(migrations_path, "2015-12-12-000000_test_migration.lua")
    local fixture_migration = [[
      return {
        name = "2015-12-12-000000_test_migration",
        up = function(options) return "" end,
        down = function(options) return "" end
      }
    ]]

    setup(function()
      local ok = IO.write_to_file(fixtures_path, fixture_migration)
      assert.truthy(ok)
      local mig_files = IO.retrieve_files(migrations_path, { file_pattern = ".lua" })
      for _, mig in ipairs(mig_files) do
        table.insert(migrations_names, mig:match("[^/]*$"))
      end

      table.sort(migrations_names)
    end)

    teardown(function()
      os.remove(fixtures_path)
    end)

    before_each(function()
      stub(env.dao_factory, "execute_queries")
      stub(env.dao_factory.migrations, "delete_migration")
      stub(env.dao_factory.migrations, "add_migration")
    end)

    it("first migration should have an init boolean property", function()
      -- `init` says to the migrations not to record changes in db for this migration
      local migration_module = loadfile(IO.path:join(migrations_path, migrations_names[1]))()
      assert.True(migration_module.init)
    end)

    describe(db_type.." #migrate()", function()

      it("1st run should execute all created migrations in order for a given dao", function()
        env.dao_factory.migrations.get_migrations = spy.new(function() return nil end)

        local i = 0
        migrations:migrate(function(migration, err)
          assert.falsy(err)
          assert.truthy(migration)
          assert.are.same(migrations_names[i+1], migration.name..".lua")
          i = i + 1
        end)

        assert.are.same(#migrations_names, i)

        -- all migrations should be recorded in db
        assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
        assert.spy(env.dao_factory.execute_queries).was.called(#migrations_names)
        assert.spy(env.dao_factory.migrations.add_migration).was.called(#migrations_names)
      end)

      describe("Partly already migrated", function()

        it("if running with some migrations pending, it should only execute the non-recorded ones", function()
          env.dao_factory.migrations.get_migrations = spy.new(function() return {migrations_names[1]} end)

          local i = 1
          migrations:migrate(function(migration, err)
            i = i + 1
            assert.falsy(err)
            assert.truthy(migration)
            assert.are.same(migrations_names[i], migration.name..".lua")
          end)

          assert.are.same(3, i)
          assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
          assert.spy(env.dao_factory.execute_queries).was.called(#migrations_names-1)
          assert.spy(env.dao_factory.migrations.add_migration).was.called(#migrations_names-1)
        end)
      end)

    end)

    describe("Already migrated", function()

      it("if running again, should detect if migrations are already up to date", function()
        env.dao_factory.migrations.get_migrations = spy.new(function() return migrations_names end)

        local i = 0
        migrations:migrate(function(migration, err)
          assert.falsy(migration)
          assert.falsy(err)
          i = i + 1
        end)

        assert.are.same(1, i)
        assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
        assert.spy(env.dao_factory.execute_queries).was_not_called()
        assert.spy(env.dao_factory.migrations.add_migration).was_not_called()
      end)
    end)

    it("should report get_migrations errors", function()
      env.dao_factory.migrations.get_migrations = spy.new(function()
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
      assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
      assert.spy(env.dao_factory.execute_queries).was_not_called()
      assert.spy(env.dao_factory.migrations.add_migration).was_not_called()
    end)

    it("should report execute_queries errors", function()
      env.dao_factory.migrations.get_migrations = spy.new(function() return {} end)
      env.dao_factory.execute_queries = spy.new(function()
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
      assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
      assert.spy(env.dao_factory.execute_queries).was.called(1)
      assert.spy(env.dao_factory.migrations.add_migration).was_not_called()
    end)

    it("should report add_migrations errors", function()
      env.dao_factory.migrations.get_migrations = spy.new(function() return {} end)
      env.dao_factory.migrations.add_migration = spy.new(function()
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
      assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
      assert.spy(env.dao_factory.execute_queries).was.called(1)
      assert.spy(env.dao_factory.migrations.add_migration).was.called(1)
    end)

    describe(db_type.." #rollback()", function()

      local old_migrations = {}

      setup(function()
        for _, f_name in ipairs(migrations_names) do
          table.insert(old_migrations, f_name:sub(0, -5))
        end
      end)

      describe("rollback latest migration", function()

        it("should only rollback the latest executed migration", function()
          env.dao_factory.migrations.get_migrations = spy.new(function() return old_migrations end)

          local i = 0
          migrations:rollback(function(migration, err)
            assert.truthy(migration)
            assert.are.same(old_migrations[#old_migrations], migration.name)
            assert.falsy(err)
            i = i + 1
          end)

          assert.are.same(1, i)
          assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
          assert.spy(env.dao_factory.execute_queries).was.called(1)
          assert.spy(env.dao_factory.migrations.delete_migration).was.called(1)
        end)

      end)

      it("should not call delete_migration if init migration is rollbacked", function()
        env.dao_factory.migrations.get_migrations = spy.new(function() return {old_migrations[1]} end)

        local i = 0
        migrations:rollback(function(migration, err)
          assert.truthy(migration)
          assert.are.same(old_migrations[1], migration.name)
          assert.falsy(err)
          i = i + 1
        end)

        assert.are.same(1, i)
        assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
        assert.spy(env.dao_factory.execute_queries).was.called(1)
        assert.spy(env.dao_factory.migrations.delete_migration).was_not_called()
      end)

      it("should report get_migrations errors", function()
        env.dao_factory.migrations.get_migrations = spy.new(function()
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
        assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
        assert.spy(env.dao_factory.execute_queries).was_not_called()
        assert.spy(env.dao_factory.migrations.delete_migration).was_not_called()
      end)

      it("should report execute_queries errors", function()
        env.dao_factory.migrations.get_migrations = spy.new(function() return old_migrations end)
        env.dao_factory.execute_queries = spy.new(function()
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
        assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
        assert.spy(env.dao_factory.execute_queries).was.called(1)
        assert.spy(env.dao_factory.migrations.delete_migration).was_not_called()
      end)

      it("should report delete_migrations errors", function()
        env.dao_factory.migrations.get_migrations = spy.new(function() return old_migrations end)
        env.dao_factory.migrations.delete_migration = spy.new(function()
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
        assert.spy(env.dao_factory.migrations.get_migrations).was.called(1)
        assert.spy(env.dao_factory.execute_queries).was.called(1)
        assert.spy(env.dao_factory.migrations.delete_migration).was.called(1)
      end)

    end)

    describe(db_type.." #reset()", function()

      local old_migrations = {}

      setup(function()
        for _, f_name in ipairs(migrations_names) do
          table.insert(old_migrations, f_name:sub(0, -5))
        end
      end)

      it("should rollback all migrations at once", function()
        local i = 0
        local expected_rollbacks = #old_migrations
        env.dao_factory.migrations.get_migrations = spy.new(function()
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
        assert.spy(env.dao_factory.migrations.get_migrations).was.called(expected_rollbacks + 1) -- becaue also run one last time to check if any more migrations
        assert.spy(env.dao_factory.execute_queries).was.called(expected_rollbacks)
        assert.spy(env.dao_factory.migrations.delete_migration).was.called(expected_rollbacks - 1) -- because doesn't run for ini migration
      end)

    end)
  end
end)
