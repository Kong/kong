local helpers = require "spec.helpers"

describe("cassandra_db", function()
  local db

  setup(function()
    local dao = assert(select(3, helpers.get_db_utils("cassandra")))
    db = dao.db
  end)

  describe("get_coordinator()", function()
    it("returns error message if no coordinator has been set", function()
      local coordinator, err = db.get_coordinator()
      assert.is_nil(coordinator)
      assert.equal("no coordinator has been set", err)
    end)

    it("doesn't return error if coordinator has been set", function()
      assert(db:first_coordinator())
      local coordinator, err = db.get_coordinator()
      assert.not_nil(coordinator)
      assert.is_nil(err)
    end)
  end)
end)
