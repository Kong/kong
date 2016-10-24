local helpers = require "spec.helpers"
local Factory = require "kong.dao.factory"

for conf, database in helpers.for_each_db() do
  describe("DAO Factory with DB: #" .. database, function()
    it("should be instanciable", function()
      local factory
      assert.has_no_errors(function()
        factory = assert(Factory.new(conf))
      end)

      assert.is_table(factory.daos)
      assert.equal(database, factory.db_type)
    end)
    it("should have shorthands to access the underlying daos", function()
      local factory = assert(Factory.new(conf))
      assert.equal(factory.daos.apis, factory.apis)
      assert.equal(factory.daos.consumers, factory.consumers)
      assert.equal(factory.daos.plugins, factory.plugins)
    end)
  end)
end
