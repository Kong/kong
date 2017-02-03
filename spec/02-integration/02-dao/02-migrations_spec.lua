local helpers = require "spec.02-integration.02-dao.helpers"
local utils = require "kong.tools.utils"

local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(kong_config)
  describe("Model migrations with DB: #"..kong_config.database, function()
    local factory
    setup(function()
      -- some `setup` functions also use `factory` and they run before the `before_each` chain
      -- hence we need to set it here, and again in `before_each`.
      factory = assert(Factory.new(kong_config))
      factory:drop_schema()
    end)

    teardown(function()
      ngx.shared.cassandra:flush_expired()
    end)

    before_each(function()
      factory = assert(Factory.new(kong_config))
    end)

    describe("current_migrations()", function()
      it("should return an empty table if no migrations have been run", function()
        local cur_migrations, err = factory:current_migrations()
        assert.falsy(err)
        assert.same({}, cur_migrations)
      end)
      if kong_config.database == "cassandra" then
        it("returns empty migrations on non-existing Cassandra keyspace", function()
          local invalid_conf = utils.shallow_copy(kong_config)
          invalid_conf.cassandra_keyspace = "_inexistent_"

          local xfactory = assert(Factory.new(invalid_conf))
          local cur_migrations, err = xfactory:current_migrations()
          assert.is_nil(err)
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

    describe("errors", function()
      it("returns errors prefixed by the DB type in __tostring()", function()
        local pg_port = kong_config.pg_port
        local cassandra_port = kong_config.cassandra_port
        local cassandra_timeout = kong_config.cassandra_timeout
        finally(function()
          kong_config.pg_port = pg_port
          kong_config.cassandra_port = cassandra_port
          kong_config.cassandra_timeout = cassandra_timeout
          ngx.shared.cassandra:flush_all()
        end)
        kong_config.pg_port = 3333
        kong_config.cassandra_port = 3333
        kong_config.cassandra_timeout = 1000

        assert.error_matches(function()
          local fact = assert(Factory.new(kong_config))
          assert(fact:run_migrations())
        end, "["..kong_config.database.." error]", nil, true)
      end)
    end)
  end)
end)
