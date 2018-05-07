local DB      = require "kong.db"
local helpers = require "spec.helpers"


-- TODO: make those tests run for all supported databases
describe("kong.db.init", function()
  describe(".new()", function()
    it("errors on invalid arg", function()
      assert.has_error(function()
        DB.new()
      end, "missing kong_config")

      assert.has_error(function()
        DB.new(helpers.test_conf, 123)
      end, "strategy must be a string")
    end)

    it("instantiates a DB", function()
      local db, err = DB.new(helpers.test_conf)
      assert.is_nil(err)
      assert.is_table(db)
    end)
  end)


  describe(":init_connector()", function()

  end)


  describe(":connect()", function()

  end)


  describe(":setkeepalive()", function()

  end)
end)
