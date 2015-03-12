local DaoError = require "kong.dao.error"

describe("DaoError", function()

  it("should be instanciable with a message and a type", function()
    local err = DaoError("error message", "some_type")
    assert.truthy(err)
    assert.truthy(err.message)
    assert.truthy(err.some_type)
  end)

  it("should return nil if trying to instanciate with an empty error message", function()
    -- this way we can directly construct a DaoError from any returned err value without testing if err is not nil first.
    local err = DaoError()
    assert.falsy(err)
  end)

  it("should print it's message property if printed", function()
    local err = DaoError("error message", "some_type")
    assert.are.same("error message", tostring(err))
  end)

  it("should print it's message property if concatenated", function()
    local err = DaoError("error message", "some_type")
    assert.are.same("error: error message", "error: "..err)
    assert.are.same("this is some error message to not ignore",  "this is some "..err.." to not ignore")
  end)

  it("should handle a table as an error message", function ()
    -- example: schema validation returns a table with key/values for errors
    local stub_error = {
      name = "name is required",
      public_dns = "invalid url"
    }

    local err = DaoError(stub_error, "some_type")
    assert.are.same("name: name is required | public_dns: invalid url", tostring(err))
  end)

end)
