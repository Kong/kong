local consumers = require "kong.db.schema.entities.consumers"
local Entity       = require "kong.db.schema.entity"

local Consumers = assert(Entity.new(consumers))

describe("consumers schema", function()
  describe("username attribute", function()
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
        local ok, err = Consumers:validate({
          username = valid_names[i],
        })
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)
  end)
end)
