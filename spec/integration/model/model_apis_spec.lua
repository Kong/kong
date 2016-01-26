local utils = require "spec.spec_helpers"
local Factory = require "kong.dao.factory"

utils.for_each_dao(function(db_type, default_options)
  describe("Model (APIs) with DB: "..db_type, function()
    local factory
    setup(function()
      factory = Factory(db_type, default_options)
    end)

    describe("insert()", function()

    end)
  end)
end)
