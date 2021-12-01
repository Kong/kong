-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local schema_def = require "kong.plugins.zipkin.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("Plugin: Zipkin (schema)", function()
  it("rejects repeated tags", function()
    local ok, err = v({
      http_endpoint = "http://example.dev",
      static_tags = {
        { name = "foo", value = "bar" },
        { name = "foo", value = "baz" },
      },
    }, schema_def)

    assert.is_falsy(ok)
    assert.same({
      config = {
        static_tags = "repeated tags are not allowed: foo"
      }
    }, err)
  end)
end)

