local helpers = require "spec.02-integration.03-dao.helpers"
local Factory = require "kong.dao.factory"
local DB = require "kong.db"

helpers.for_each_dao(function(kong_conf)
  describe("DAO Factory with DB: #" .. kong_conf.database, function()
    it("should be instanciable", function()
      local factory
      assert.has_no_errors(function()
        factory = assert(Factory.new(kong_conf, DB.new(kong_conf)))
      end)

      assert.is_table(factory.daos)
      assert.equal(kong_conf.database, factory.db_type)
    end)
    it("should have shorthands to access the underlying daos", function()
      local factory = assert(Factory.new(kong_conf, DB.new(kong_conf)))
      assert.equal(factory.daos.apis, factory.apis)
      assert.equal(factory.daos.consumers, factory.consumers)
      assert.equal(factory.daos.plugins, factory.plugins)
    end)
  end)

  describe(":init()", function()
    it("returns DB-specific error string", function()
      local pg_port = kong_conf.pg_port
      local cassandra_port = kong_conf.cassandra_port

      finally(function()
        kong_conf.pg_port = pg_port
        kong_conf.cassandra_port = cassandra_port
      end)

      kong_conf.pg_port = 9999
      kong_conf.cassandra_port = 9999

      local factory = assert(Factory.new(kong_conf, DB.new(kong_conf)))
      local ok, err = factory:init()
      assert.is_nil(ok)
      assert.matches("[" .. kong_conf.database .. " error]", err, 1, true)
    end)
  end)

  describe(":init() + :infos()", function()
    it("returns DB info + 'unknown' for version if missing", function()
      local factory = assert(Factory.new(kong_conf, DB.new(kong_conf)))
      local info = factory:infos()

      if kong_conf.database == "postgres" then
        assert.same({
          db_name = "PostgreSQL",
          desc = "database",
          name = kong_conf.pg_database,
          version = "unknown",
        }, info)

      elseif kong_conf.database == "cassandra" then
        assert.same({
          db_name = "Cassandra",
          desc = "keyspace",
          name = kong_conf.cassandra_keyspace,
          version = "unknown",
        }, info)

      else
        error("unknown database")
      end
    end)

    it("returns DB version if :init() called", function()
      local factory = assert(Factory.new(kong_conf, DB.new(kong_conf)))
      assert(factory:init())

      local info = factory:infos()
      assert.is_string(info.version)
      -- should be <major>.<minor>
      assert.matches("%d+%.%d+", info.version)
    end)

    it("calls :check_version_compat()", function()
      local factory = assert(Factory.new(kong_conf, DB.new(kong_conf)))
      local s = spy.on(factory, "check_version_compat")

      factory:init()

      assert.spy(s).was_called()
    end)

    if kong_conf.database == "cassandra" then
      it("[cassandra] sets the 'major_version_n' field on the DB", function()
        local factory = assert(Factory.new(kong_conf, DB.new(kong_conf)))
        assert(factory:init())

        assert.is_number(factory.db.major_version_n)
      end)
    end
  end)

  describe(":check_version_compat()", function()
    local factory
    local db_name

    before_each(function()
      factory = assert(Factory.new(kong_conf, DB.new(kong_conf)))

      local db_infos = factory:infos()
      db_name = db_infos.db_name
    end)

    it("errors if init() was not called", function()
      local ok, err = factory:check_version_compat()
      assert.is_nil(ok)
      assert.equal("could not check database compatibility: version " ..
                   "is unknown (did you call ':init'?)", err)
    end)

    describe("db_ver < min", function()
      it("errors", function()
        local versions_to_test = {
          "1.0",
          "9.0",
          "9.3",
        }

        for _, v in ipairs(versions_to_test) do
          factory.db.major_minor_version = v

          local ok, err = factory:check_version_compat("10.0")
          assert.is_nil(ok)
          assert.equal("Kong requires " .. db_name .. " 10.0 or greater " ..
                       "(currently using " .. v .. ")", err)
        end
      end)
    end)

    describe("db_ver < deprecated < min", function()
      it("errors", function()
        local versions_to_test = {
          "1.0",
          "9.0",
          "9.3",
        }

        for _, v in ipairs(versions_to_test) do
          factory.db.major_minor_version = v

          local ok, err = factory:check_version_compat("10.0", "9.4")
          assert.is_nil(ok)
          assert.equal("Kong requires " .. db_name .. " 10.0 or greater " ..
                       "(currently using " .. v .. ")", err)
        end
      end)
    end)

    describe("deprecated <= db_ver < min", function()
      it("logs deprecation warning", function()
        local log = require "kong.cmd.utils.log"
        local s = spy.on(log, "log")

        local versions_to_test = {
          "9.3",
          "9.4",
        }

        for _, v in ipairs(versions_to_test) do
          factory.db.major_minor_version = v

          local ok, err = factory:check_version_compat("9.5", "9.3")
          assert.is_nil(err)
          assert.is_true(ok) -- no error on deprecation notices
          assert.spy(s).was_called_with(log.levels.warn,
            "Currently using %s %s which is considered deprecated, " ..
            "please use %s or greater", db_name, v, "9.5")
        end
      end)
    end)

    describe("min < deprecated <= db_ver", function()
      -- Note: constants should not be configured in this fashion, but this
      -- test is for robustness's sake
      it("fine", function()
        local versions_to_test = {
          "10.0",
          "11.1",
        }

        for _, v in ipairs(versions_to_test) do
          factory.db.major_minor_version = v

          local ok, err = factory:check_version_compat("9.4", "10.0")
          assert.is_nil(err)
          assert.is_true(ok)
        end
      end)
    end)

    describe("deprecated < min <= db_ver", function()
      it("fine", function()
        local versions_to_test = {
          "9.5",
          "10.0",
          "11.1",
        }

        for _, v in ipairs(versions_to_test) do
          factory.db.major_minor_version = v

          local ok, err = factory:check_version_compat("9.5", "9.4")
          assert.is_nil(err)
          assert.is_true(ok)
        end
      end)
    end)

    it("asserts current constants", function()
      -- current min versions hard-coded in the tests to see them fail when we
      -- update the constants
      factory.db.major_minor_version = kong_conf.database == "postgres" and
                                       "9.5" or "2.2"

      local constants = require "kong.constants"
      local db_constants = constants.DATABASE[kong_conf.database:upper()]

      local ok, err = factory:check_version_compat(db_constants.MIN,
                                                   db_constants.DEPRECATED)
      assert.is_nil(err)
      assert.is_true(ok)
    end)
  end)
end)
