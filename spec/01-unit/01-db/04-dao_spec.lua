local Schema = require("kong.db.schema.init")
local Entity = require("kong.db.schema.entity")
local DAO = require("kong.db.dao.init")
local errors = require("kong.db.errors")
local utils = require("kong.tools.utils")

local null = ngx.null

local nullable_schema_definition = {
  name = "Foo",
  primary_key = { "a" },
  fields = {
    { a = { type = "number" }, },
    { b = { type = "string", default = "hello" }, },
    { u = { type = "string" }, },
    { r = { type = "record",
            required = false,
            fields = {
              { f1 = { type = "number" } },
              { f2 = { type = "string", default = "world" } },
            } } },
  }
}

local non_nullable_schema_definition = {
  name = "Foo",
  primary_key = { "a" },
  fields = {
    { a = { type = "number" }, },
    { b = { type = "string", default = "hello", required = true }, },
    { u = { type = "string" }, },
    { r = { type = "record",
            fields = {
              { f1 = { type = "number" } },
              { f2 = { type = "string", default = "world", required = true } },
            } } },
  }
}

local ttl_schema_definition = {
  name = "Foo",
  ttl = true,
  primary_key = { "a" },
  fields = {
    { a = { type = "number" }, },
  }
}

local optional_cache_key_fields_schema = {
  name = "Foo",
  primary_key = { "a" },
  cache_key = { "b", "u" },
  fields = {
    { a = { type = "number" }, },
    { b = { type = "string" }, },
    { u = { type = "string" }, },
  },
}

local mock_db = {}


describe("DAO", function()

  describe("select", function()

    it("applies defaults if strategy returns column as nil and is nullable in schema", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local strategy = {
        select = function()
          return { a = 42, b = nil, r = { f1 = 10 } }
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      local row = dao:select({ a = 42 })
      assert.same(42, row.a)
      assert.same("hello", row.b)
      assert.same(10, row.r.f1)
      assert.same("world", row.r.f2)
    end)

    it("applies defaults if strategy returns column as nil and is not nullable in schema", function()
      local schema = assert(Schema.new(non_nullable_schema_definition))

      -- mock strategy
      local strategy = {
        select = function()
          return { a = 42, b = nil, r = { f1 = 10 } }
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      local row = dao:select({ a = 42 })
      assert.same(42, row.a)
      assert.same("hello", row.b)
      assert.same(10, row.r.f1)
      assert.same("world", row.r.f2)
    end)

    it("applies defaults if strategy returns column as null and is not nullable in schema", function()
      local schema = assert(Schema.new(non_nullable_schema_definition))

      -- mock strategy
      local strategy = {
        select = function()
          return { a = 42, b = null, r = { f1 = 10, f2 = null } }
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      local row = dao:select({ a = 42 })
      assert.same(42, row.a)
      assert.same("hello", row.b)
      assert.same(10, row.r.f1)
      assert.same("world", row.r.f2)
    end)

    it("preserves null if strategy returns column as null and is nullable in schema", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local strategy = {
        select = function()
          return { a = 42, b = null, r = { f1 = 10, f2 = null } }
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      local row = dao:select({ a = 42 }, { nulls = true })
      assert.same(42, row.a)
      assert.same(null, row.b)
      assert.same(10, row.r.f1)
      assert.same(null, row.r.f2)
    end)

    it("only returns a null ttl if nulls is given (#5185)", function()
      local schema = assert(Schema.new(ttl_schema_definition))

      -- mock strategy
      local strategy = {
        select = function()
          return { a = 42, ttl = null }
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      local row = dao:select({ a = 42 }, { nulls = true })
      assert.same(42, row.a)
      assert.same(null, row.ttl)

      row = dao:select({ a = 42 }, { nulls = false })
      assert.same(42, row.a)
      assert.same(nil, row.ttl)
    end)
  end)

  describe("update", function()

    it("does not pre-apply defaults on partial update if field is nullable in schema", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          -- no defaults pre-applied before partial update
          assert(value.b == nil)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = nil, u = nil, r = nil }
      local row, err = dao:update({ a = 43 }, { u = "foo" })
      assert.falsy(err)
      assert.same({ a = 42, b = "hello", u = "foo" }, row)
    end)

    it("does not pre-apply defaults on record fields if field is nullable in schema", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          -- no defaults pre-applied before partial update
          assert(value.r.f2 == nil)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = nil, u = nil, r = nil }
      local row, err = dao:update({ a = 43 }, { u = "foo", r = { f1 = 10 } })
      assert.falsy(err)
      assert.same({ a = 42, b = "hello", u = "foo", r = { f1 = 10, f2 = "world" } }, row)
    end)

    it("always returns the structure of records when using Entities", function()
      local entity = assert(Entity.new(non_nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          -- no defaults pre-applied before partial update
          assert(value.b == nil)
          assert(value.r == nil or value.r.f2 == nil)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, entity, strategy, errors)

      data = { a = 42, b = nil, u = nil, r = nil }
      local row, err = dao:update({ a = 42 }, { u = "foo" }, { nulls = true })
      assert.falsy(err)
      assert.same({ a = 42, b = "hello", u = "foo", r = { f1 = ngx.null, f2 = "world" } }, row)
    end)

    it("does not apply defaults on entity if record is nullable in schema", function()
      local schema = assert(Schema.new(non_nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        update = function(_, _, value)
          -- no defaults pre-applied before partial update
          assert(value.b == nil)
          assert(value.r == nil or value.r.f2 == nil)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = nil, u = nil, r = nil }
      local row, err = dao:update({ a = 42 }, { u = "foo" }, { nulls = true })
      assert.falsy(err)
      -- defaults are applied when returning the full updated entity
      assert.same({ a = 42, b = "hello", u = "foo", r = null }, row)
    end)

    it("applies defaults on entity for record in Entity", function()
      local schema = assert(Entity.new(non_nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = nil, u = nil, r = nil }
      local row, err = dao:update({ a = 42 }, { u = "foo" }, { nulls = true })
      assert.falsy(err)
      -- defaults are applied when returning the full updated entity
      assert.same({ a = 42, b = "hello", u = "foo", r = { f1 = null, f2 = "world" } }, row)

      -- likewise for record update:

      data = { a = 42, b = nil, u = nil, r = nil }
      row, err = dao:update({ a = 43 }, { u = "foo", r = { f1 = 10 } })
      assert.falsy(err)
      assert.same({ a = 42, b = "hello", u = "foo", r = { f1 = 10, f2 = "world" } }, row)
    end)

    it("applies defaults if strategy returns column as null and is not nullable in schema", function()
      local schema = assert(Schema.new(non_nullable_schema_definition))

      -- mock strategy
      local strategy = {
        update = function()
          return { a = 42, b = null, r = { f1 = 10, f2 = null } }
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      local row = dao:update({ a = 42 }, { u = "foo" })
      assert.same(42, row.a)
      assert.same("hello", row.b)
      assert.same(10, row.r.f1)
      assert.same("world", row.r.f2)
    end)

    it("preserves null if strategy returns column as null and is nullable in schema", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        update = function(_, _, value)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = null, u = null, r = null }
      local row, err = dao:update({ a = 42 }, { u = "foo" }, { nulls = true })
      assert.falsy(err)
      assert.same({ a = 42, b = null, u = "foo", r = null }, row)
    end)

    it("sets default in r.f2 when setting r.f1 and r is currently nil", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = null, u = null, r = nil }
      local row, err = dao:update({ a = 43 }, { u = "foo", r = { f1 = 10 } }, { nulls = true })
      assert.falsy(err)
      assert.same({ a = 42, b = null, u = "foo", r = { f1 = 10, f2 = "world" } }, row)
    end)

    it("sets default in r.f2 when setting r.f1 and r is currently nil", function()
      local schema = assert(Schema.new(non_nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = nil, u = null, r = nil }
      local row, err = dao:update({ a = 43 }, { u = "foo", r = { f1 = 10 } }, { nulls = true })
      assert.falsy(err)
      assert.same({ a = 42, b = "hello", u = "foo", r = { f1 = 10, f2 = "world" } }, row)
    end)

    it("sets default in r.f2 when setting r.f1 and r is currently null", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = null, u = nil, r = nil }
      local row, err = dao:update({ a = 43 }, { u = "foo", r = { f1 = 10 } }, { nulls = true })
      assert.falsy(err)
      assert.same({ a = 42, b = null, u = "foo", r = { f1 = 10, f2 = "world" } }, row)
    end)

    it("preserves null in r.f2 when setting r.f1", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      -- setting r.f2 as an explicit null
      data = { a = 42, b = null, u = null, r = { f1 = 9, f2 = null } }
      local row, err = dao:update({ a = 43 }, { u = "foo", r = { f1 = 10, f2 = null } }, { nulls = true })
      assert.falsy(err)
      assert.same({ a = 42, b = null, u = "foo", r = { f1 = 10, f2 = null } }, row)
    end)
  end)

  describe("cache_key", function()

    it("converts null in composite cache_key to empty string", function()
      local schema = assert(Schema.new(optional_cache_key_fields_schema))
      local dao = DAO.new(mock_db, schema, {}, errors)

      -- setting u as an explicit null
      local data = { a = 42, b = "foo", u = null }
      local cache_key = dao:cache_key(data)
      assert.equals("Foo:foo::::", cache_key)
    end)

    it("converts nil in composite cache_key to empty string", function()
      local schema = assert(Schema.new(optional_cache_key_fields_schema))
      local dao = DAO.new(mock_db, schema, {}, errors)

      local data = { a = 42, b = "foo", u = nil }
      local cache_key = dao:cache_key(data)
      assert.equals("Foo:foo::::", cache_key)
    end)
  end)
end)
