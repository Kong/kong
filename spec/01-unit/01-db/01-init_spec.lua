local db = require "kong.dao.db"

describe("kong.dao.db.init", function()
  it("has __index set to the init module so we can call base functions", function()
    local my_db_module = db.new_db("cassandra")

    function my_db_module.new()
      local self = my_db_module.super.new()
      self.foo = "bar"
      return self
    end

    local my_db = my_db_module.new()
    assert.equal("bar", my_db.foo)

    assert.has_no_error(function()
      my_db:init()
      my_db:init_worker()
    end)
  end)
end)
