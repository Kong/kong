local Schema = require "kong.db.schema"
local event_hooks = require "kong.db.schema.entities.event_hooks"
local event_hooks_subschemas = require "kong.db.schema.entities.event_hooks_subschemas"

local Event_hooks = assert(Schema.new(event_hooks))

for k, v in pairs(event_hooks_subschemas) do
  assert(Event_hooks:new_subschema(k, v))
end

describe("event_hooks (schema)", function()
  describe("lambda subschema", function()
    it("accepts valid lua code", function()
      local entity = {
        event = "foo",
        source = "bar",
        handler = "lambda",
        config = {
          functions = {
            [[ return function() end ]],
          }
        }
      }
      assert.truthy(Event_hooks:validate(entity))
    end)

    it("rejects invalid lua code", function()
      local entity = {
        event = "foo",
        source = "bar",
        handler = "lambda",
        config = {
          functions = {
            [[ YOLO ]],
          }
        }
      }
      assert.falsy(Event_hooks:validate(entity))
    end)
  end)
end)
