local helpers = require "spec.02-integration.03-dao.helpers"
local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(kong_conf)
  describe("DAO Factory with DB: #" .. kong_conf.database, function()
    it("should be instanciable", function()
      local factory
      assert.has_no_errors(function()
        factory = assert(Factory.new(kong_conf))
      end)

      assert.is_table(factory.daos)
      assert.equal(kong_conf.database, factory.db_type)
    end)
    it("should have shorthands to access the underlying daos", function()
      local factory = assert(Factory.new(kong_conf))
      assert.equal(factory.daos.apis, factory.apis)
      assert.equal(factory.daos.consumers, factory.consumers)
      assert.equal(factory.daos.plugins, factory.plugins)
    end)
  end)

  describe(":init() + :infos()", function()
    it("returns DB info + 'unknown' for version if missing", function()
      local factory = assert(Factory.new(kong_conf))
      local info = factory:infos()

      if kong_conf.database == "postgres" then
        assert.same({
          desc = "database",
          name = kong_conf.pg_database,
          version = "unknown",
        }, info)

      elseif kong_conf.database == "cassandra" then
        assert.same({
          desc = "keyspace",
          name = kong_conf.cassandra_keyspace,
          version = "unknown",
        }, info)

      else
        error("unknown database")
      end
    end)

    it("returns DB version if :init() called", function()
      local factory = assert(Factory.new(kong_conf))
      assert(factory:init())

      local info = factory:infos()
      assert.is_string(info.version)
      assert.not_equal("unknown", info.version)
    end)
  end)
end)
