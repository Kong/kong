-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local plugin_schema = require "kong.plugins.exit-transformer.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("exit-transformer schema", function()
  it("requires a functions argument", function()
    local entity, err = v({}, plugin_schema)
    assert.is_falsy(entity)
    assert.not_nil(err)
  end)

  it("accepts a functions argument", function()
    local config = {
      functions = {
        [[ return function () end ]],
        [[ return function () end ]],
      }
    }
    local entity, err = v(config, plugin_schema)
    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("validates functions argument", function()
    local config = {
      functions = {
        [[ some non valid lua code ]],
      }
    }
    local entity, err = v(config, plugin_schema)
    assert.is_falsy(entity)
    assert.not_nil(err)
  end)
end)
