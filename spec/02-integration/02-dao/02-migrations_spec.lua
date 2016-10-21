local helpers = require "spec.helpers"
local Factory = require "kong.dao.factory"
local utils = require "kong.tools.utils"

for conf, database in helpers.for_each_db() do
  describe("Model migrations with DB: #"..database, function()
    local factory
    setup(function()
      factory = assert(Factory.new(conf))
      factory:drop_schema()
    end)

    describe("current_migrations()", function()
      it("should return an empty table if no migrations have been run", function()
        local cur_migrations, err = factory:current_migrations()
        assert.falsy(err)
        assert.same({}, cur_migrations)
      end)
      if database == "cassandra" then
        -- Postgres wouldn't be able to connect to a non-existing
        -- database at all, so we only test this for Cassandra.
        it("returns empty migrations on non-existing Cassandra keyspace", function()
          local invalid_conf = utils.shallow_copy(conf)
          invalid_conf.cassandra_keyspace = "_inexistent_"

          local xfactory = assert(Factory.new(invalid_conf))
          local cur_migrations = assert(xfactory:current_migrations())
          assert.same({}, cur_migrations)
        end)
      end
    end)

    describe("migrations_modules()", function()
      it("should return the core migrations", function()
        local migrations = factory:migrations_modules()
        assert.is_table(migrations)
        assert.is_table(migrations.core)
        assert.True(#migrations.core > 0)
      end)
    end)

    ---
    -- Integration behavior.
    -- Must run in order.
    describe("[INTEGRATION]", function()
      local total_migrations = 0
      local flatten_migrations = {}
      setup(function()
        for identifier, migs in pairs(factory:migrations_modules()) do
          total_migrations = total_migrations + 1
          for _, mig in ipairs(migs) do
            flatten_migrations[#flatten_migrations+1] = {
              identifier = identifier,
              name = mig.name
            }
          end
        end
      end)
      it("should run the migrations with callbacks", function()
        local on_migration = spy.new(function() end)
        local on_success = spy.new(function() end)

        assert(factory:run_migrations(on_migration, on_success))

        assert.spy(on_migration).was_called(total_migrations)
        assert.spy(on_success).was_called(#flatten_migrations)

        for _, mig in ipairs(flatten_migrations) do
          assert.spy(on_migration).was_called_with(mig.identifier, factory:infos())
          assert.spy(on_success).was_called_with(mig.identifier, mig.name, factory:infos())
        end
      end)
      it("should return the migrations recorded as executed", function()
        local cur_migrations = assert(factory:current_migrations())

        assert(next(cur_migrations), "no migrations were executed")
        assert.is_table(cur_migrations.core)
      end)
      it("should not run any migration on subsequent run", function()
        local on_migration = spy.new(function() end)
        local on_success = spy.new(function() end)

        assert(factory:run_migrations())

        assert.spy(on_migration).was_not_called()
        assert.spy(on_success).was_not_called()
      end)
    end)

    describe("errors", function()
      it("returns errors prefixed by the DB type in __tostring()", function()
        local invalid_conf = utils.shallow_copy(conf)
        invalid_conf.pg_port = 3333
        invalid_conf.cassandra_port = 3333
        invalid_conf.cassandra_timeout = 1000

        assert.error_matches(function()
          local fact = assert(Factory.new(invalid_conf))
          assert(fact:run_migrations())
        end, "["..database.." error]", nil, true)
      end)
    end)
  end)
end
