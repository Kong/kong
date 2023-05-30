-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Entity = require("kong.db.schema.entity")
local DAO = require("kong.db.dao.init")
local errors = require("kong.db.errors")
local utils = require("kong.tools.utils")

local DEFAULT_WORKSPACE = "4d5435cb-5f92-42c0-ace3-752a78550126"

local basic_schema_definition = {
  name = "basic",
  primary_key = { "a" },
  fields = {
    { a = { type = "number" }, },
    { b = { type = "string" }, },
  }
}

local mock_db = {}

local mock_kong = {
  configuration = {
  },

  -- random UUID
  default_workspace = DEFAULT_WORKSPACE,

  db = {
    workspaces = {
      select = function()
        return { id = DEFAULT_WORKSPACE }
      end
    }
  }
}


-- FIXME: The unix domain socket is not available in busted,
-- so we need to pause this test until we find a solution.
describe("option no_broadcast_crud_event", function()
  local old_meta_table

  lazy_setup(function ()
    if kong then
      old_meta_table = getmetatable(_G.kong)
      setmetatable(_G.kong, mock_kong)

    else
      _G.kong = mock_kong
    end
  end)

  lazy_teardown(function ()
    if old_meta_table then
      setmetatable(_G.kong, old_meta_table)

    else
      _G.kong = nil
    end
  end)

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
          data = utils.cycle_aware_deep_merge(data, value)
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
          data = utils.cycle_aware_deep_merge(data, value)
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
