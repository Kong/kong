local workspaces = require "kong.db.schema.entities.workspaces"
local Entity       = require "kong.db.schema.entity"

local Workspaces = assert(Entity.new(workspaces))

describe("workspaces schema", function()
  describe("name attribute", function()
    -- refusals
    it("rejects invalid names", function()
      local invalid_names = {
        "examp:le",
        "examp;le",
        "examp/le",
        "examp le",
        -- see tests for utils.validate_utf8 for more invalid values
        string.char(105, 213, 205, 149),
      }

      for i = 1, #invalid_names do
        local ok, err = Workspaces:validate({
          name = invalid_names[i],
          config = {},
          meta = {},
        })
        assert.falsy(ok)
        assert.matches("invalid", err.name)
      end
    end)

    -- acceptance
    it("accepts valid names", function()
      local valid_names = {
        "example",
        "EXAMPLE",
        "exa.mp.le",
        "3x4mp13",
        "3x4-mp-13",
        "3x4_mp_13",
        "~3x4~mp~13",
        "~3..x4~.M-p~1__3_",
        "孔",
        "Конг",
        "🦍",
      }

      for i = 1, #valid_names do
        local ok, err = Workspaces:validate({
          name = valid_names[i],
          config = {},
          meta = {},
        })
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)
  end)
end)
