local Errors = require "kong.dao.errors"
local constants = require "kong.constants"

describe("Errors", function()
  for _, v in pairs(constants.DB_ERROR_TYPES) do
    it("should be possible to instanciate a "..v.." error", function()
      local err = Errors[v]("err txt")
      assert.is_table(err)
    end)
    it("should have a field set to true to represent its type", function()
      local err = Errors[v]("err txt")
      assert.True(err[v])
    end)
    it("should have a message string", function()
      local err = Errors[v]("err txt")
      assert.is_string(err.message)
      assert.equal("err txt", err.message)
    end)
    it("should not have a err_tbl", function()
      local err = Errors[v]("err txt")
      assert.falsy(err.err_tbl)
    end)
    it("should return nil if trying to instanciate with nil", function()
      -- sugar if we don't want to check if err_msg ~= nil
      local err = Errors[v]()
      assert.falsy(err)
    end)
    it("should not wrap another error, but return the original one", function()
      local err = Errors[v]("original error")
      local err2 = Errors[v](err)
      assert.same(err, err2)
    end)
    it("should be printable", function()
      local err = Errors[v]("some error")
      assert.equal("some error", tostring(err))
    end)
    it("should be concatenable", function()
      local err = Errors[v]("some error")
      assert.equal("foo some error", "foo "..err)
      assert.equal("some error foo", err.." foo")
    end)
    if v ~= constants.DB_ERROR_TYPES.UNIQUE then
      it("should handle a table as error message", function()
        local tbl = {
          foo = "foostr",
          bar = "barstr"
        }
        local err = Errors[v](tbl)
        assert.same(tbl, err.err_tbl)
        assert.is_string(err.message)
        assert.equal("foo=foostr bar=barstr", err.message)
      end)
    end
  end

  describe("unique", function()
    it("create a unique error", function()
      local tbl = {
        name = "foo",
        unique_field = "bar"
      }
      local err = Errors.unique(tbl)
      assert.True(err.unique)
      assert.same({
        name = "already exists with value 'foo'",
        unique_field = "already exists with value 'bar'"
      }, err.err_tbl)
      assert.equal("name=already exists with value 'foo' unique_field=already exists with value 'bar'", tostring(err))
    end)
  end)
end)
