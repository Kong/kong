local helpers = require "spec.helpers"


describe("DAO db/cassandra.lua #cassandra", function()
  local cassandra_db


  lazy_setup(function()
    local dao = select(3, helpers.get_db_utils("cassandra"))
    cassandra_db = dao.db
  end)


  describe("get_coordinator()", function()
    it("returns error message if no coordinator has been set", function()
      local coordinator, err = cassandra_db:get_coordinator()
      assert.is_nil(coordinator)
      assert.equal("no coordinator has been set", err)
    end)


    it("doesn't return error if coordinator has been set", function()
      assert(cassandra_db:first_coordinator())
      local coordinator, err = cassandra_db:get_coordinator()
      assert.not_nil(coordinator)
      assert.is_nil(err)
    end)
  end)
end)
