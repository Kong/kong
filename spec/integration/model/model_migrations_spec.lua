local inspect = require "inspect"

local utils = require "kong.tools.utils"
local helpers = require "spec.spec_helpers"
_G.ngx = nil

local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(db_type, default_opts, TYPES)
  describe("["..db_type:upper().."] Model migrations", function()
    local factory
    before_each(function()
      factory = Factory(db_type, default_opts)
    end)
    after_each(function()

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
        assert.falsy(cur_migrations)
        assert.is_string(err)

        if db_type == TYPES.CASSANDRA then
          assert.truthy(string.find(err, "Keyspace '_inexistent_' does not exist."))
        elseif db_type == TYPES.POSTGRES then
          assert.equal('FATAL: database "_inexistent_" does not exist', err)
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
  end)
end)
