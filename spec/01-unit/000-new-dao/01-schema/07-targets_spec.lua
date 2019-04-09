local Schema = require "kong.db.schema"
local targets = require "kong.db.schema.entities.targets"
local upstreams = require "kong.db.schema.entities.upstreams"
local utils = require "kong.tools.utils"

assert(Schema.new(upstreams))
local Targets = assert(Schema.new(targets))

local function validate(b)
  return Targets:validate(Targets:process_auto_fields(b, "insert"))
end


describe("targets", function()
  describe("targets.target", function()
    it("validates", function()
      local upstream = { id = utils.uuid() }
      local targets = { "valid.name", "valid.name:8080", "12.34.56.78", "1.2.3.4:123" }
      for _, target in ipairs(targets) do
        local ok, err = validate({ target = target, upstream = upstream })
        assert.is_true(ok)
        assert.is_nil(err)
      end

      local ok, err = validate({ target = "\\\\bad\\\\////name////", upstream = upstream })
      assert.falsy(ok)
      assert.same({ target = "Invalid target; not a valid hostname or ip address"}, err)
    end)
  end)
end)
