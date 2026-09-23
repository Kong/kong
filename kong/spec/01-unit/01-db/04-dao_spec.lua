local Schema = require("kong.db.schema.init")
local Entity = require("kong.db.schema.entity")
local DAO = require("kong.db.dao.init")
local errors = require("kong.db.errors")
local hooks = require("kong.hooks")
local cycle_aware_deep_merge = require("kong.tools.table").cycle_aware_deep_merge

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

local parent_cascade_delete_schema = {
  name = "Foo",
  primary_key = { "a" },
  fields = {
    { a = { type = "number" }, },
  },
}

local cascade_delete_schema = {
  name = "Bar",
  primary_key = { "b" },
  fields = {
    { b = { type = "number" }, },
    { c = { type = "foreign", reference = "Foo", on_delete = "cascade" }, },
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

    it("does pre-apply defaults on partial update if field is nullable in schema", function()
      local schema = assert(Schema.new(nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          -- defaults pre-applied before partial update
          assert(value.b == "hello")
          data = cycle_aware_deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = nil, u = nil, r = nil }
      local row, err = dao:update({ a = 42 }, { u = "foo" })
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
          data = cycle_aware_deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, schema, strategy, errors)

      data = { a = 42, b = nil, u = nil, r = nil }
      local row, err = dao:update({ a = 42 }, { u = "foo", r = { f1 = 10 } })
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
          -- defaults pre-applied before partial update
          assert.equal("hello", value.b)
          assert.same({
            f1 = null,
            f2 = "world",
          }, value.r)
          data = cycle_aware_deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, entity, strategy, errors)

      data = { a = 42, b = nil, u = nil, r = nil }
      local row, err = dao:update({ a = 42 }, { u = "foo" }, { nulls = true })
      assert.falsy(err)
      assert.same({ a = 42, b = "hello", u = "foo", r = { f1 = ngx.null, f2 = "world" } }, row)
    end)

    it("does apply defaults on entity if record is nullable in schema", function()
      local schema = assert(Schema.new(non_nullable_schema_definition))

      -- mock strategy
      local data
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          -- defaults pre-applied before partial update
          assert.equal("hello", value.b)
          assert.same(null, value.r)
          data = cycle_aware_deep_merge(data, value)
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
          data = cycle_aware_deep_merge(data, value)
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
        select = function()
          return {}
        end,
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
        select = function()
          return data
        end,
        update = function(_, _, value)
          data = cycle_aware_deep_merge(data, value)
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
          data = cycle_aware_deep_merge(data, value)
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
          data = cycle_aware_deep_merge(data, value)
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
          data = cycle_aware_deep_merge(data, value)
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
          data = cycle_aware_deep_merge(data, value)
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

  describe("delete", function()

    lazy_setup(function()

      local kong_global = require "kong.global"
      _G.kong = kong_global.new()

    end)

    it("deletes the entity and cascades the delete notifications", function()
      local parent_schema = assert(Schema.new(parent_cascade_delete_schema))
      local child_schema = assert(Schema.new(cascade_delete_schema))

      -- mock strategy
      local data = { a = 42, b = nil, u = nil, r = nil }
      local child_strategy = {
        each_for_c = function()
          return {}, nil
        end,
        page_for_c = function()
          return {}, nil
        end
      }
      local child_dao = DAO.new(mock_db, child_schema, child_strategy, errors)
      mock_db = {
        daos = {
          Bar = child_dao
        }
      }

      local parent_strategy = {
        select = function()
          return data
        end,
        delete = function(pk, _)
          -- assert.are.same({ a = 42 }, pk)
          return nil, nil
        end
      }
      local parent_dao = DAO.new(mock_db, parent_schema, parent_strategy, errors)

      local _, err = parent_dao:delete({ a = 42 })
      assert.falsy(err)
    end)


    it("find_cascade_delete_entities()", function()
      local parent_schema = assert(Schema.new({
        name = "Foo",
        primary_key = { "a" },
        fields = {
          { a = { type = "number" }, },
        }
      }))

      local child_schema = assert(Schema.new({
        name = "Bar",
        primary_key = { "b" },
        fields = {
          { b = { type = "number" }, },
          { c = { type = "foreign", reference = "Foo", on_delete = "cascade" }, },
        }
      }))

      local parent_strategy = setmetatable({}, {__index = function() return function() end end})
      local child_strategy = parent_strategy
      local child_dao = DAO.new(mock_db, child_schema, child_strategy, errors)

      child_dao.each_for_c = function()
        local i = 0
        return function()
          i = i + 1
          if i == 1 then
            return { c = 40 }
          end
        end
      end


      -- Create grandchild schema
      local grandchild_schema = assert(Schema.new({
        name = "Dar",
        primary_key = { "d" },
        fields = {
          { d = { type = "number" }, },
          { e = { type = "foreign", reference = "Bar", on_delete = "cascade" }, },
        }
      }))

      local parent_strategy = setmetatable({}, {__index = function() return function() end end})
      local grandchild_strategy = parent_strategy
      local grandchild_dao = DAO.new(mock_db, grandchild_schema, grandchild_strategy, errors)

      grandchild_dao.each_for_e = function()
        local i = 0
        return function()
          i = i + 1
          -- We have 3 grand child entities
          if i <= 3 then
            return { e = 50 + i }
          end
        end
      end

      -- Create great_grandchild schema
      local great_grandchild_schema = assert(Schema.new({
        name = "Far",
        primary_key = { "f" },
        fields = {
          { f = { type = "number" }, },
          { g = { type = "foreign", reference = "Dar", on_delete = "cascade" }, },
        }
      }))

      local parent_strategy = setmetatable({}, {__index = function() return function() end end})
      local great_grandchild_strategy = parent_strategy
      local great_grandchild_dao = DAO.new(mock_db, great_grandchild_schema, great_grandchild_strategy, errors)

      great_grandchild_dao.each_for_g = function()
        local i = 0
        return function()
          i = i + 1
          -- We have 3 great grand child entities
          if i <= 3 then
            return { g = 60 + i }
          end
        end
      end

      mock_db = {
        daos = {
          Bar = child_dao,
          Dar = grandchild_dao,
          Far = great_grandchild_dao,
        }
      }

      local parent_dao = DAO.new(mock_db, parent_schema, parent_strategy, errors)
      local parent_entity = {}
      local entries = DAO._find_cascade_delete_entities(parent_dao, parent_entity, { show_ws_id = true })
      assert.equal(#entries, 13)
      -- Entry 1 should be the child `c` entity which references the parent `Foo` DAO
      assert.equal(40, entries[1].entity.c)
      -- Entry 2 should be the grandchild `e` entity which references the child `Bar` DAO
      assert.equal(51, entries[2].entity.e)
      -- Entries 3 to 5 should be the great grandchild `g` entity which references the grandchild `Dar` DAO
      assert.equal(61, entries[3].entity.g)
      assert.equal(62, entries[4].entity.g)
      assert.equal(63, entries[5].entity.g)
      -- Entry 6 should be the grandchild `e` entity which references the child `Bar` DAO
      assert.equal(52, entries[6].entity.e)
      -- Entries 7 to 9 should be the great grandchild `g` entity which references the grandchild `Dar` DAO
      assert.equal(61, entries[7].entity.g)
      assert.equal(62, entries[8].entity.g)
      assert.equal(63, entries[9].entity.g)
      -- Entry 10 should be the grandchild `e` entity which references the child `Bar` DAO
      assert.equal(53, entries[10].entity.e)
      -- Entries 11 to 13 should be the great grandchild `g` entity which references the grandchild `Dar` DAO
      assert.equal(61, entries[11].entity.g)
      assert.equal(62, entries[12].entity.g)
      assert.equal(63, entries[13].entity.g)
    end)

    it("should call post-delete hook once after concurrent delete", function()
      finally(function()
        hooks.clear_hooks()
      end)

      local post_hook = spy.new(function() end)
      local delete_called = false

      hooks.register_hook("dao:delete:post", function()
        post_hook()
      end)

      local schema = Schema.new({
        name = "Baz",
        primary_key = { "id" },
        fields = {
          { id = { type = "number" } },
        }
      })

      local strategy = {
        select = function()
          return { id = 1 }
        end,
        delete = function(pk, _)
          if not delete_called then
            delete_called = true
            return true
          end

          return nil
        end
      }

      local dao = DAO.new({}, schema, strategy, errors)

      dao:delete({ id = 1 })
      dao:delete({ id = 1 })

      assert.spy(post_hook).was_called(2)
    end)
  end)

  describe("cache_key", function()

    it("converts null in composite cache_key to empty string", function()
      local schema = assert(Schema.new(optional_cache_key_fields_schema))
      local dao = DAO.new(mock_db, schema, {}, errors)

      -- setting u as an explicit null
      local data = { a = 42, b = "foo", u = null }
      local cache_key = dao:cache_key(data)
      assert.equals("Foo:foo:::::", cache_key)
    end)

    it("converts nil in composite cache_key to empty string", function()
      local schema = assert(Schema.new(optional_cache_key_fields_schema))
      local dao = DAO.new(mock_db, schema, {}, errors)

      local data = { a = 42, b = "foo", u = nil }
      local cache_key = dao:cache_key(data)
      assert.equals("Foo:foo:::::", cache_key)
    end)

    it("fallbacks to primary_key if nothing in cache_key is found", function()
      local schema = assert(Schema.new(optional_cache_key_fields_schema))
      local dao = DAO.new(mock_db, schema, {}, errors)

      local data = { a = 42 }
      local cache_key = dao:cache_key(data)
      assert.equals("Foo:42:::::", cache_key)
    end)

  end)
end)
