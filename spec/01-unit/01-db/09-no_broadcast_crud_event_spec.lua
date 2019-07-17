local Entity = require("kong.db.schema.entity")
local DAO = require("kong.db.dao.init")
local errors = require("kong.db.errors")
local utils = require("kong.tools.utils")

local basic_schema_definition = {
  name = "basic",
  primary_key = { "a" },
  fields = {
    { a = { type = "number" }, },
    { b = { type = "string" }, },
  }
}

local mock_db = {}


describe("option no_broadcast_crud_event", function()

  describe("update", function()
    it("does not trigger a CRUD event when true", function()
      local entity = assert(Entity.new(basic_schema_definition))

      -- mock strategy
      local data = { a = 42, b = "hello" }
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, entity, strategy, errors)

      dao.events = {
        post_local = spy.new(function() end)
      }

      local row, err = dao:update({ a = 42 }, { b = "world" }, { no_broadcast_crud_event = true })
      assert.falsy(err)
      assert.same({ a = 42, b = "world" }, row)

      row, err = dao:select({ a = 42 })
      assert.falsy(err)
      assert.same({ a = 42, b = "world" }, row)

      assert.spy(dao.events.post_local).was_not_called()
    end)

    it("triggers a CRUD event when false", function()
      local entity = assert(Entity.new(basic_schema_definition))

      -- mock strategy
      local data = { a = 42, b = "hello" }
      local strategy = {
        select = function()
          return data
        end,
        update = function(_, _, value)
          data = utils.deep_merge(data, value)
          return data
        end,
      }

      local dao = DAO.new(mock_db, entity, strategy, errors)

      dao.events = {
        post_local = spy.new(function() end)
      }

      local row, err = dao:update({ a = 42 }, { b = "three" }, { no_broadcast_crud_event = false })
      assert.falsy(err)
      assert.same({ a = 42, b = "three" }, row)

      assert.spy(dao.events.post_local).was_called(1)

      local row, err = dao:update({ a = 42 }, { b = "four" })
      assert.falsy(err)
      assert.same({ a = 42, b = "four" }, row)

      assert.spy(dao.events.post_local).was_called(2)

    end)
  end)
end)
