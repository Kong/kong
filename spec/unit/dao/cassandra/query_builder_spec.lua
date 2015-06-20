local builder = require "kong.dao.cassandra.query_builder"

describe("Query Builder", function()

  local apis_details = {
    primary_key = {"id"},
    clustering_key = {"cluster_key"},
    indexes = {public_dns = true, name = true}
  }

  describe("SELECT", function()

    it("should build a SELECT query", function()
      local q = builder.select("apis")
      assert.equal("SELECT * FROM apis", q)
    end)

    it("should restrict columns to SELECT", function()
      local q = builder.select("apis", nil, nil, {"name", "id"})
      assert.equal("SELECT name, id FROM apis", q)
    end)

    it("should return the columns of the arguments to bind", function()
      local _, columns = builder.select("apis", {name="mockbin", public_dns="mockbin.com"})
      assert.same({"name", "public_dns"}, columns)
    end)

    describe("WHERE", function()
      it("should not allow filtering if all the queried fields are indexed", function()
        local q, _, needs_filtering = builder.select("apis", {name="mockbin"}, apis_details)
        assert.equal("SELECT * FROM apis WHERE name = ?", q)
        assert.False(needs_filtering)
      end)

      it("should not allow filtering if all the queried fields are primary keys", function()
        local q, _, needs_filtering = builder.select("apis", {id="1"}, apis_details)
        assert.equal("SELECT * FROM apis WHERE id = ?", q)
        assert.False(needs_filtering)
      end)

      it("should not allow filtering if all the queried fields are primary keys or indexed", function()
        local q, _, needs_filtering = builder.select("apis", {id="1", name="mockbin"}, apis_details)
        assert.equal("SELECT * FROM apis WHERE name = ? AND id = ?", q)
        assert.False(needs_filtering)
      end)

      it("should not allow filtering if all the queried fields are primary keys or indexed", function()
        local q = builder.select("apis", {id="1", name="mockbin", cluster_key="foo"}, apis_details)
        assert.equal("SELECT * FROM apis WHERE cluster_key = ? AND name = ? AND id = ?", q)
      end)

      it("should enable filtering when more than one indexed field is being queried", function()
        local q, _, needs_filtering = builder.select("apis", {name="mockbin", public_dns="mockbin.com"}, apis_details)
        assert.equal("SELECT * FROM apis WHERE name = ? AND public_dns = ? ALLOW FILTERING", q)
        assert.True(needs_filtering)
      end)
    end)

    it("should throw an error if no column_family", function()
      assert.has_error(function()
        builder.select()
      end, "column_family must be a string")
    end)

    it("should throw an error if select_columns is not a table", function()
      assert.has_error(function()
        builder.select("apis", {name="mockbin"}, nil, "")
      end, "select_columns must be a table")
    end)

    it("should throw an error if primary_key is not a table", function()
      assert.has_error(function()
        builder.select("apis", {name="mockbin"}, {primary_key = ""})
      end, "primary_key must be a table")
    end)

    it("should throw an error if indexes is not a table", function()
      assert.has_error(function()
        builder.select("apis", {name="mockbin"}, {indexes = ""})
      end, "indexes must be a table")
    end)

    it("should throw an error if where_key is not a table", function()
      assert.has_error(function()
        builder.select("apis", "")
      end, "where_t must be a table")
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
      local q = builder.update("apis", {name="mockbin"}, {id="1"}, apis_details)
      assert.equal("UPDATE apis SET name = ? WHERE id = ?", q)
    end)

    it("should return the columns of the arguments to bind", function()
      local _, columns = builder.update("apis", {public_dns="1234", name="mockbin"}, {id="1"}, apis_details)
      assert.same({"public_dns", "name", "id"}, columns)
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

      assert.has_error(function()
        builder.update("apis", {})
      end, "update_values cannot be empty")
    end)

    it("should throw an error if no where_t", function()
      assert.has_error(function()
        builder.update("apis", {name="foo"}, {})
      end, "where_t must contain keys")
    end)

  end)

  describe("DELETE", function()

    it("should build a DELETE query", function()
      local q = builder.delete("apis", {id="1234"})
      assert.equal("DELETE FROM apis WHERE id = ?", q)
    end)

    it("should return the columns of the arguments to bind", function()
      local _, columns = builder.delete("apis", {id="1234"})
      assert.same({"id"}, columns)
    end)

    it("should throw an error if no column_family", function()
      assert.has_error(function()
        builder.delete()
      end, "column_family must be a string")
    end)

    it("should throw an error if no where_t", function()
      assert.has_error(function()
        builder.delete("apis", {})
      end, "where_t must contain keys")
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

