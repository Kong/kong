local utils = require "spec.spec_helpers"
local Factory = require "kong.dao.factory"

utils.for_each_dao(function(db_type, default_options)
  describe("Model Factory with DB: "..db_type, function()
    it("should be instanciable", function()
      local factory
      assert.has_no_errors(function()
        factory = Factory(db_type, default_options)
      end)

      assert.True(factory:is(Factory))
      assert.is_table(factory.models)
      assert.equal(db_type, factory.db_type)
    end)
  end)
end)
