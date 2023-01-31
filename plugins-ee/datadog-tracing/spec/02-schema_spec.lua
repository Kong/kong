-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local schema_def = require "kong.plugins.datadog-tracing.schema"
local validate_plugin_config_schema = require "spec.helpers".validate_plugin_config_schema

describe("Plugin: datadog-tracing (schema)", function()
  it("accepts empty config", function()
    local _, err = validate_plugin_config_schema({}, schema_def)
    assert.is_nil(err)
  end)

  it("accepts endpoint with token", function()
    local _, err = validate_plugin_config_schema({
      endpoint = "http://token@localhost:8126/v0.4/traces?api_key=123"
    }, schema_def)
    assert.is_nil(err)
  end)
end)
