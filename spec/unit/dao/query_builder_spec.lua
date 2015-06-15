local builder = require "kong.dao.cassandra.query_builder"

describe("Query Builder", function()
  describe("SELECT", function()

    it("should build a SELECT query", function()
      local q = builder.select("apis")
      assert.equal("SELECT * FROM apis", q)
    end)

    it("should accept SELECT keys", function()
      local q = builder.select("apis", nil, nil, {"name", "id"})
      assert.equal("SELECT name, id FROM apis", q)
    end)

    it("should build a WHERE fragment", function()
      local q = builder.select("apis", {name="mockbin", public_dns="mockbin.com"}, nil, {"name", "id"})
      assert.equal("SELECT name, id FROM apis WHERE name = ? AND public_dns = ?", q)
    end)

    it("should add ALLOW FILTERING if necessary", function()
      local q = builder.select("apis", {name="mockbin", public_dns="mockbin.com"}, {"id"})
      assert.equal("SELECT * FROM apis WHERE name = ? AND public_dns = ? ALLOW FILTERING", q)
    end)

    it("should return the columns of the arguments to bind", function()
      local _, columns = builder.select("apis", {name="mockbin", public_dns="mockbin.com"}, {"name", "id"})
      assert.same({"name", "public_dns"}, columns)
    end)

    it("should throw an error if no column_family", function()
      assert.has_error(function()
        builder.select()
      end, "column_family must be a string")
    end)

    it("should return an error if select_columns is not a table", function()
      assert.has_error(function()
        builder.select("apis", nil, nil, "")
      end, "select_columns must be a table")
    end)

  end)

  describe("INSERT", function()

    it("should build an INSERT query", function()
      local q = builder.insert("apis", {id="123", name="mockbin"})
      assert.equal("INSERT INTO apis(name, id) VALUES(?, ?)", q)
    end)

    it("should return the columns of the arguments to bind", function()
      local _, columns = builder.insert("apis", {id="123", name="mockbin"})
      assert.same({"name", "id"}, columns)
    end)

    it("should throw an error if no column_family", function()
      assert.has_error(function()
        builder.insert(nil, {"id", "name"})
      end, "column_family must be a string")
    end)

    it("should throw an error if no insert_values", function()
      assert.has_error(function()
        builder.insert("apis")
      end, "insert_values must be a table")
    end)

  end)

  describe("UPDATE", function()

    it("should build an UPDATE query", function()
      local q = builder.update("apis", {id="1234", name="mockbin"})
      assert.equal("UPDATE apis SET name = ?, id = ?", q)
    end)

    it("should build a WHERE fragment", function()
      local q = builder.update("apis", {id="1234", name="mockbin"}, {id="1", name="httpbin"})
      assert.equal("UPDATE apis SET name = ?, id = ? WHERE name = ? AND id = ?", q)
    end)

    it("should return the columns of the arguments to bind", function()
      local _, columns = builder.update("apis", {id="1234", name="mockbin"})
      assert.same({"name", "id"}, columns)

      _, columns = builder.update("apis", {id="1234", name="mockbin"}, {id="1", name="httpbin"})
      assert.same({"name", "id", "name", "id"}, columns)
    end)

    it("should throw an error if no column_family", function()
      assert.has_error(function()
        builder.update()
      end, "column_family must be a string")
    end)

    it("should throw an error if no update_values", function()
      assert.has_error(function()
        builder.update("apis")
      end, "update_values must be a table")
    end)

  end)

  describe("DELETE", function()

    it("should build a WHERE fragment", function()
      local q = builder.delete("apis", {name="mockbin"})
      assert.equal("DELETE FROM apis WHERE name = ?", q)
    end)

    it("should return the columns of the arguments to bind", function()
      local _, columns = builder.delete("apis", {name="mockbin"})
      assert.same({"name"}, columns)
    end)

    it("should throw an error if no column_family", function()
      assert.has_error(function()
        builder.delete()
      end, "column_family must be a string")
    end)

    it("should throw an error if no where_t", function()
      assert.has_error(function()
        builder.delete("apis")
      end, "where_t must be a table")
    end)

  end)

  describe("TRUNCATE", function()

    it("should build a TRUNCATE query", function()
      local q = builder.truncate("apis")
      assert.equal("TRUNCATE apis", q)
    end)

    it("should throw an error if no column_family", function()
      assert.has_error(function()
        builder.truncate()
      end, "column_family must be a string")
    end)

  end)
end)
