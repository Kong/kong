require "spec.helpers" -- initialize kong globals expected by kong.db modules

local iteration = require "kong.db.iteration"


describe("kong.db.iteration", function()
  describe(".by_row()", function()
    it("keeps fetching pages when a page returns fewer rows than `size` " ..
       "but still reports an offset (regression)", function()
      -- Regression test: some strategies (e.g. the `off`/DB-less strategy)
      -- may drop rows from a page (for example, expired TTL'd entities)
      -- while still returning a non-nil offset because more raw entries
      -- remain to be read. The iterator used to assume `#rows == size`
      -- whenever an offset was present, and stopped early in that case.
      local pages = {
        { rows = { { id = 1 } }, offset = "cursor-1" },
        { rows = { { id = 2 }, { id = 3 } }, offset = nil },
      }

      local call_count = 0
      local function pager(size, offset, options)
        call_count = call_count + 1
        local page = pages[call_count]
        assert.is_not_nil(page, "pager called more times than expected")
        return page.rows, nil, page.offset
      end

      local fake_dao = { schema = { name = "test_entities" } }
      local next_row = iteration.by_row(fake_dao, pager, 2, nil)

      local ids = {}
      while true do
        local row, err = next_row()
        assert.is_nil(err)
        if not row then
          break
        end
        table.insert(ids, row.id)
      end

      assert.same({ 1, 2, 3 }, ids)
      assert.equal(2, call_count)
    end)
  end)
end)
