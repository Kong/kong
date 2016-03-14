local utils = require "kong.tools.utils"
local helpers = require "spec.spec_helpers"

local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(db_type, default_opts, TYPES)
  describe("Model migrations with DB: #"..db_type, function()
    local factory
    setup(function()
      local f = Factory(db_type, default_opts)
      f:drop_schema()
    end)
    before_each(function()
      factory = Factory(db_type, default_opts)
    end)

    describe("current_migrations()", function()
      it("should return an empty table if no migrations have run", function()
        local cur_migrations, err = factory:current_migrations()
        assert.falsy(err)
        assert.same({}, cur_migrations)
      end)
      it("should return errors", function()
        local invalid_opts = utils.shallow_copy(default_opts)
        if db_type == TYPES.CASSANDRA then
          invalid_opts.keyspace = "_inexistent_"
        elseif db_type == TYPES.POSTGRES then
          invalid_opts.database = "_inexistent_"
        end

        local xfactory = Factory(db_type, invalid_opts)

        local cur_migrations, err = xfactory:current_migrations()
        if db_type == TYPES.CASSANDRA then
          assert.same({}, cur_migrations)
        elseif db_type == TYPES.POSTGRES then
          assert.truthy(err)
          assert.falsy(cur_migrations)
          assert.True(err.db)
          assert.equal('FATAL: database "_inexistent_" does not exist', tostring(err))
        end
      end)
    end)

    describe("migrations_modules()", function()
      it("should return the core migrations", function()
        local migrations = factory:migrations_modules()
        assert.is_table(migrations)
        assert.is_table(migrations.core)
        assert.True(#migrations.core > 0)
      end)
    end)

    describe("run_migrations()", function()
      teardown(function()
        factory:drop_schema()
      end)
      it("should run the migrations from an empty DB", function()
        local ok, err = factory:run_migrations()
        assert.falsy(err)
        assert.True(ok)
      end)
    end)

    ---
    -- Integration behavior.
    -- Must run in order.
    describe("[INTEGRATION]", function()
      local flatten_migrations = {}
      setup(function()
        factory:drop_schema()
        for identifier, migs in pairs(factory:migrations_modules()) do
          for _, mig in ipairs(migs) do
            flatten_migrations[#flatten_migrations + 1] = {identifier = identifier, name = mig.name}
          end
        end
      end)
      teardown(function()
        factory:drop_schema()
      end)
      it("should run the migrations with callbacks", function()
        local on_migration = spy.new(function() end)
        local on_success = spy.new(function() end)

        local ok, err = factory:run_migrations(on_migration, on_success)
        assert.falsy(err)
        assert.True(ok)

        assert.spy(on_migration).was_called(1)
        assert.spy(on_success).was_called(#flatten_migrations)

        for _, mig in ipairs(flatten_migrations) do
          assert.spy(on_migration).was_called_with(mig.identifier)
          assert.spy(on_success).was_called_with(mig.identifier, mig.name)
        end
      end)
      it("should return the migrations recorded as executed", function()
        local cur_migrations, err = factory:current_migrations()
        assert.falsy(err)

        assert.truthy(next(cur_migrations))
        assert.is_table(cur_migrations.core)
      end)
      it("should not run any migration on subsequent run", function()
        local on_migration = spy.new(function() end)
        local on_success = spy.new(function() end)

        local ok, err = factory:run_migrations()
        assert.falsy(err)
        assert.True(ok)

        assert.spy(on_migration).was_not_called()
        assert.spy(on_success).was_not_called()
      end)
    end)
  end)
end)
