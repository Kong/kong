-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

describe("bundled plugins schema validation", function()
  it("ensure every bundled plugin schema must have protocols field", function()
    local EE_BUNDLED_PLUGINS = require("distribution.distributions_constants").plugins
    for _, plugin_name in pairs(EE_BUNDLED_PLUGINS) do
      local schema = require("plugins-ee." .. plugin_name .. ".kong.plugins." .. plugin_name .. ".schema")
      local has_protocols_field
      for _, field in ipairs(schema.fields) do
        if field.protocols then
          has_protocols_field = true
          break
        end
      end
      assert.is_true(has_protocols_field, "bundled plugin " .. plugin_name .. " missing required field: protocols")
    end
  end)

end)
