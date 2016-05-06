local helpers = require "spec.integration.02-dao.helpers"
local utils = require "kong.tools.utils"

local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(kong_config)
  describe("Model migrations with DB: #"..kong_config.database, function()
    local factory
    setup(function()
      local f = Factory(kong_config)
      f:drop_schema()
    end)
    before_each(function()
      factory = Factory(kong_config)
    end)

    describe("current_migrations()", function()
      it("should return an empty table if no migrations have run", function()
        local cur_migrations, err = factory:current_migrations()
        assert.falsy(err)
        assert.same({}, cur_migrations)
      end)
      pending("should return errors", function()
        local invalid_conf = utils.shallow_copy(kong_config)
        if invalid_conf.database == "cassandra" then
          invalid_conf.cassandra_keyspace = "_inexistent_"
        elseif invalid_conf.database == "postgres" then
          invalid_conf.pg_database = "_inexistent_"
        end

        local xfactory = Factory(invalid_conf)

        local cur_migrations, err = xfactory:current_migrations()
        if kong_config.database == "cassandra" then
          assert.same({}, cur_migrations)
        elseif kong_config.database == "postgres" then
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
      local n_ids = 0
      local flatten_migrations = {}
      setup(function()
        factory:drop_schema()
        for identifier, migs in pairs(factory:migrations_modules()) do
          n_ids = n_ids + 1
          for _, mig in ipairs(migs) do
            flatten_migrations[#flatten_migrations + 1] = {
              identifier = identifier,
              name = mig.name
            }
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

        assert.spy(on_migration).was_called(n_ids)
        assert.spy(on_success).was_called(#flatten_migrations)

        for _, mig in ipairs(flatten_migrations) do
          assert.spy(on_migration).was_called_with(mig.identifier, factory:infos())
          assert.spy(on_success).was_called_with(mig.identifier, mig.name, factory:infos())
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
