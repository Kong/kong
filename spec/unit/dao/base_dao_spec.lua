local BaseDAO = require "kong.base.dao"

describe("BaseDAO #dao", function()
  it("should be instanciable", function()
    local base_dao = BaseDAO({})
    assert.truthy(base_dao)
    assert.same({}, base_dao.schema)
  end)
  describe("instance", function()
    local base_dao
    before_each(function()
      base_dao = BaseDAO({}, {option_foo = "foo"}, nil)
    end)
    it("should have :get_session_options() return a copy of session_options", function()
      assert.is_function(base_dao.get_session_options)

      local session_options = base_dao:get_session_options()
      assert.same({option_foo = "foo"}, session_options)

      session_options.option_foo = "bar"
      assert.not_same(session_options, base_dao:get_session_options())
    end)
    it(":execute() is abstract", function()
      assert.has_error(base_dao.execute, "execute() is abstract and must be implemented in a subclass")
    end)
  end)
end)
