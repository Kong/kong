describe("ee meta", function()
  local ee_dao_factory = require "kong.enterprise_edition.dao.factory"
  local vitals = require "kong.vitals"
  local rl = require "kong.tools.public.rate-limiting"

  setup(function()
    stub(vitals, "table_names").returns({"v1", "v2", "v3"})
    stub(rl, "table_names").returns({"rl1", "rl2", "rl3"})
  end)

  teardown(function()
    vitals.table_names:revert()
    rl.table_names:revert()
  end)

  describe("additional_tables", function()
    it("returns a table", function()
      assert.is_table(ee_dao_factory.additional_tables())
    end)

    it("it merges vitals and rate-limiting tables names", function()
      local t_names = ee_dao_factory.additional_tables()
      local expected = {
        "v1", "v2", "v3", "rl1", "rl2", "rl3"
      }

      assert.same(t_names, expected)
    end)
  end)
end)
