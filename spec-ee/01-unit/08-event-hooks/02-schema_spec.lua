-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Schema = require "kong.db.schema"
local event_hooks_schema = require "kong.db.schema.entities.event_hooks"
local event_hooks_subschemas = require "kong.db.schema.entities.event_hooks_subschemas"

local event_hooks = require "kong.enterprise_edition.event_hooks"

local Event_hooks = assert(Schema.new(event_hooks_schema))

for k, v in pairs(event_hooks_subschemas) do
  assert(Event_hooks:new_subschema(k, v))
end

describe("event_hooks (schema)", function()
  -- reset any mocks, stubs, whatever was messed up on _G.kong and event-hooks
  before_each(function()
    _G.kong = {
      configuration = {
        event_hooks_enabled = true,
      },
      worker_events = {},
      log = mock(setmetatable({}, { __index = function() return function() end end })),
    }

    for k, v in pairs(event_hooks.events) do
      event_hooks.events[k] = nil
    end

    for k, v in pairs(event_hooks.references) do
      event_hooks.references[k] = nil
    end

    mock.revert(event_hooks)
    mock.revert(kong)
  end)
  describe("lambda subschema", function()
    before_each(function()
      event_hooks.publish("bar", "foo")
    end)

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
