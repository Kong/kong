local Errors = require "kong.dao.errors"

describe("Errors", function()
  describe("unique()", function()
    it("creates a unique error", function()
      local err = Errors.unique {name = "foo", unique_field = "bar"}
      assert.is_table(err)
      assert.True(err.unique)
      assert.equal("already exists with value 'foo'", err.tbl.name)
      assert.equal("already exists with value 'bar'", err.tbl.unique_field)
      assert.equal("name=already exists with value 'foo' unique_field=already exists with value 'bar'", err.message)
      assert.equal(err.message, tostring(err))
    end)
  end)

  describe("foreign()", function()
    it("creates a foreign error", function()
      local err = Errors.foreign {foreign_a = "foo", foreign_b = "bar"}
      assert.is_table(err)
      assert.True(err.foreign)
      assert.equal("does not exist with value 'foo'", err.tbl.foreign_a)
      assert.equal("does not exist with value 'bar'", err.tbl.foreign_b)
      assert.equal("foreign_a=does not exist with value 'foo' foreign_b=does not exist with value 'bar'", err.message)
      assert.equal(err.message, tostring(err))
    end)
  end)

  describe("schema()", function()
    it("create a schema error", function()
      local err = Errors.schema {field_a = "invalid", field_b = "bar"}
      assert.is_table(err)
      assert.True(err.schema)
      assert.equal("invalid", err.tbl.field_a)
      assert.equal("bar", err.tbl.field_b)
    end)
  end)

  describe("db()", function()
    it("create a db error", function()
      local err = Errors.db "invalid response"
      assert.is_table(err)
      assert.True(err.db)
      assert.equal("invalid response", err.message)
    end)
  end)
end)
