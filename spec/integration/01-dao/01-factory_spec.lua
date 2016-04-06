local helpers = require "spec.integration.01-dao.helpers"
local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(kong_conf)
  describe("Model Factory with DB: #"..kong_conf.database, function()
    it("should be instanciable", function()
      local factory
      assert.has_no_errors(function()
        factory = Factory(kong_conf)
      end)

      assert.True(factory:is(Factory))
      assert.is_table(factory.daos)
      assert.equal(kong_conf.database, factory.db_type)
    end)
    it("should have shorthands to access the underlying daos", function()
      local factory = Factory(kong_conf)
      assert.equal(factory.daos.apis, factory.apis)
      assert.equal(factory.daos.consumers, factory.consumers)
      assert.equal(factory.daos.plugins, factory.plugins)
    end)
  end)
end)
