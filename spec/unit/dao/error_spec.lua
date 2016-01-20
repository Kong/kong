local DaoError = require "kong.dao.error"
local constants = require "kong.constants"

describe("DaoError #dao", function()
  it("should be instanciable with a message and a type", function()
    local err = DaoError("error message", "some_type")
    assert.truthy(err)
    assert.truthy(err.message)
    assert.truthy(err.some_type)
    assert.truthy(err.is_dao_error)
  end)
  it("should have an error code if the error comes from the database driver", function()
    local error_mt = {}
    error_mt = {
      __tostring = function(self)
        return self.message
      end,
      __concat = function (a, b)
        if getmetatable(a) == error_mt then
          return a.message .. b
        else
          return a .. b.message
        end
      end
    }

    local function cassandra_error(message, code, raw_message)
      local err = {message=message, code=code, raw_message=raw_message}
      setmetatable(err, error_mt)
      return err
    end

    local err = DaoError(cassandra_error("some error", 1234), constants.DATABASE_ERROR_TYPES.DATABASE)
    assert.truthy(err.cassandra_err_code)
  end)
  it("should return nil if trying to instanciate with an empty error message", function()
    -- this way we can directly construct a DaoError from any returned err value without testing if err is not nil first.
    local err = DaoError()
    assert.falsy(err)
  end)
  it("should print its message property if printed", function()
    local err = DaoError("error message", "some_type")
    assert.are.same("error message", tostring(err))
  end)
  it("should print its message property if concatenated", function()
    local err = DaoError("error message", "some_type")
    assert.are.same("error: error message", "error: "..err)
    assert.are.same("this is some error message to not ignore",  "this is some "..err.." to not ignore")
  end)
  it("should handle a table as an error message", function ()
    -- example: schema validation returns a table with key/values for errors
    local stub_error = {
      name = "name is required",
      request_host = "invalid url"
    }

    local err = DaoError(stub_error, "some_type")
    assert.are.same("name=name is required request_host=invalid url", tostring(err))
  end)
end)
